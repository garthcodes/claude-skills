---
description: Assess the impact of a production bug (scope, duration, affected data) and generate a rake task to remediate any data issues
argument-hint: <fault-id-or-description> [root-cause-summary]
---

# Impact Assessment & Data Remediation

Assess the real-world impact of a production bug and create scripts to diagnose and fix any data damage. This skill is designed to run **after** the root cause is known — typically after `/fix-honeybadger` or `/debug` has identified the problem.

## Prerequisites

Before running this skill, you should already know:
- The Honeybadger fault ID (or error details)
- The root cause of the bug
- What the fix looks like (or it's already implemented)

If the root cause is not yet known, run `/fix-honeybadger` or `/debug` first.

## Key Constraint

Claude does **not** have access to the production database. This skill produces two scripts:
1. **Diagnostic script** — user runs in production, outputs JSON with affected record IDs and details
2. **Remediation rake task** — accepts the diagnostic output as input, fixes the affected records

This ensures all data in the impact assessment is real production data, never estimates.

**You never run these against production yourself.** You author the diagnostic script and remediation rake task; the user executes them in production (or explicitly approves each command — the `claude-hook-prod-guard.py` hook pauses any production-targeting command for approval).

## Phase 1: Gather Impact Data from Honeybadger

### Step 1: Identify the Fault

If `$ARGUMENTS` includes a Honeybadger fault ID, use it directly. Otherwise, find the relevant fault:

```
mcp__honeybadger__list_projects
mcp__honeybadger__list_faults(project_id: <id>, q: "<error class or description>")
```

### Step 2: Collect Scope Data

Gather comprehensive impact metrics using the Honeybadger MCP tools:

```
# Fault details (occurrences, first/last seen)
mcp__honeybadger__get_fault(project_id: <id>, fault_id: <fault_id>)

# All affected users with occurrence counts
mcp__honeybadger__list_fault_affected_users(project_id: <id>, fault_id: <fault_id>)

# Recent notices for request context and patterns
mcp__honeybadger__list_fault_notices(project_id: <id>, fault_id: <fault_id>)

# Occurrence trends over time
mcp__honeybadger__get_project_occurrence_counts(project_id: <id>, period: "day")

# Notices by user breakdown
mcp__honeybadger__get_project_report(project_id: <id>, report: "notices_by_user", start: "<first_seen>", stop: "<now>")
```

### Step 3: Compile Duration Timeline

Build a timeline from the data:

1. **Bug introduced**: Check git history for when the causal change was deployed
   ```bash
   git log --oneline --after="<date_before_first_seen>" --before="<first_seen_date>" -- <affected_files>
   ```
2. **First occurrence**: From Honeybadger fault `created_at`
3. **Last occurrence**: From Honeybadger fault `last_notice_at`
4. **Fix deployed**: When the fix PR was merged/deployed (or "pending" if not yet deployed)

Calculate the **exposure window** (time between bug introduction and fix deployment).

## Phase 2: Assess Data Impact

### Step 4: Determine Data Damage

Based on the root cause, answer these questions:

1. **Was data corrupted?** — Did the bug cause incorrect values to be written to the database?
2. **Was data lost?** — Did the bug prevent data from being saved that should have been?
3. **Was data duplicated?** — Did the bug cause duplicate records?
4. **Were side effects skipped?** — Did the bug prevent callbacks, emails, notifications, or jobs from firing?
5. **Were external systems affected?** — Did bad data flow to Stripe, Stedi, Google Calendar, or other integrations?

For each "yes", identify:
- Which models/tables are affected
- How to query for affected records
- How to determine the correct state

## Phase 3: Create the Diagnostic Script

### Step 5: Design the Diagnostic Script

Create a rake task that the user runs in production to discover affected records. This script:
- **Only reads data** — never writes or modifies anything
- **Outputs JSON to stdout** — structured data that can be piped to the remediation task
- **Scoped to the exposure window** — only queries records within the affected time range
- **Tenant-aware** — uses `ActsAsTenant.without_tenant` to query across all organizations
- **PHI-safe** — outputs record IDs and minimal metadata, no client names/DOBs/etc.

### Step 6: Implement the Diagnostic Script

**File**: `lib/tasks/diagnose_<short_description>.rake`

```ruby
# lib/tasks/diagnose_<short_description>.rake
namespace :data do
  desc "Diagnose data affected by Honeybadger fault #<fault_id>: <short description>"
  task diagnose_<short_description>: :environment do
    results = {
      fault_id: <fault_id>,
      description: "<what this diagnoses>",
      exposure_window: {
        start: "<first_seen>",
        stop: "<last_seen>"
      },
      diagnosed_at: Time.current.iso8601,
      affected_records: []
    }

    ActsAsTenant.without_tenant do
      scope = ModelName.where(created_at: "<first_seen>".."<last_seen>")
        .where(<condition_matching_potentially_affected>)

      $stderr.puts "Scanning #{scope.count} potentially affected records..."

      scope.find_each do |record|
        # Determine if this record is actually affected
        next unless <condition_confirming_damage>(record)

        results[:affected_records] << {
          id: record.id,
          model: record.class.name,
          organization_id: record.organization_id,
          # Include fields needed by the remediation task to apply the fix
          current_value: record.<damaged_field>,
          expected_value: <how_to_determine_correct_value>(record)
          # Add any other fields the remediation task needs
        }
      end
    end

    results[:total_affected] = results[:affected_records].size
    $stderr.puts "Found #{results[:total_affected]} affected records."

    # Output JSON to stdout so it can be captured and passed to remediation
    puts results.to_json
  end
end
```

**Key design decisions:**
- Progress/status messages go to `$stderr` so they don't pollute the JSON on `$stdout`
- The JSON includes everything the remediation task needs — record IDs, current values, expected values
- Each record entry includes `organization_id` so the remediation task can set tenant context

## Phase 4: Create the Remediation Rake Task

### Step 7: Design the Remediation Rake Task

The rake task accepts the diagnostic JSON as input and fixes the identified records. It must be:

- **Input-driven**: Only fixes records identified by the diagnostic script — no independent querying
- **Idempotent**: Safe to run multiple times without causing additional damage
- **Dry-run by default**: Print what would change unless `DRY_RUN=false` is passed
- **Logged**: Print clear output for every record processed
- **Tenant-aware**: Set `ActsAsTenant.current_tenant` per record using the `organization_id` from the diagnostic output

### Step 8: Implement the Remediation Rake Task

**File**: `lib/tasks/remediate_<short_description>.rake`

```ruby
# lib/tasks/remediate_<short_description>.rake
namespace :data do
  desc "Remediate data affected by Honeybadger fault #<fault_id>: <short description>"
  task remediate_<short_description>: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    input_file = ENV.fetch("INPUT") { abort "ERROR: Pass INPUT=path/to/diagnosis.json or pipe from stdin" }

    diagnosis = JSON.parse(
      input_file == "-" ? $stdin.read : File.read(input_file)
    )

    affected_records = diagnosis["affected_records"]

    puts "=" * 60
    puts "Remediation: <description of what this fixes>"
    puts "Honeybadger Fault: ##{diagnosis['fault_id']}"
    puts "Diagnosis from: #{diagnosis['diagnosed_at']}"
    puts "Records to process: #{affected_records.size}"
    puts "Mode: #{dry_run ? 'DRY RUN (pass DRY_RUN=false to apply)' : 'LIVE — changes will be applied'}"
    puts "=" * 60
    puts

    fixed_count = 0
    skipped_count = 0
    error_count = 0

    affected_records.each do |entry|
      record_id = entry["id"]
      model_class = entry["model"].constantize
      org = Organization.find(entry["organization_id"])

      ActsAsTenant.with_tenant(org) do
        record = model_class.find_by(id: record_id)

        unless record
          puts "  [SKIP] #{entry['model']} ##{record_id}: record not found (already deleted?)"
          skipped_count += 1
          next
        end

        # Check if the record still needs fixing (idempotency)
        unless <condition_still_needs_fix>(record, entry)
          puts "  [SKIP] #{entry['model']} ##{record_id}: already correct"
          skipped_count += 1
          next
        end

        if dry_run
          puts "  [DRY RUN] Would fix #{entry['model']} ##{record_id}: " \
               "#{entry['current_value']} -> #{entry['expected_value']}"
        else
          begin
            record.update!(<corrected_attributes_from_entry>(entry))
            fixed_count += 1
            puts "  [FIXED] #{entry['model']} ##{record_id}: " \
                 "#{entry['current_value']} -> #{entry['expected_value']}"
          rescue => e
            error_count += 1
            puts "  [ERROR] #{entry['model']} ##{record_id}: #{e.message}"
          end
        end
      end
    end

    puts
    puts "=" * 60
    puts "Results:"
    puts "  Records in diagnosis: #{affected_records.size}"
    puts "  Skipped:              #{skipped_count}"
    if dry_run
      puts "  Would fix:            #{affected_records.size - skipped_count}"
      puts
      puts "To apply changes:"
      puts "  bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json DRY_RUN=false"
    else
      puts "  Fixed:                #{fixed_count}"
      puts "  Errors:               #{error_count}"
    end
    puts "=" * 60
  end
end
```

### Step 9: Verify the Rake Tasks

1. **Verify both tasks compile** — ensure they load without syntax errors:
   ```bash
   bundle exec rake -T data:diagnose_<short_description> data:remediate_<short_description>
   ```

2. **Review the logic** — walk through query scope, conditions, JSON structure, and fix logic

## Phase 5: Present Impact Report & Get Confirmation

### Step 10: Generate Impact Summary

Present the assessment to the user. Note that record counts will be filled in after they run the diagnostic script.

```
## Impact Assessment: Honeybadger Fault #<fault_id>

### Scope (from Honeybadger)
- **Error**: `<ErrorClass>` — <error message>
- **Total occurrences**: <count>
- **Affected users**: <count>
- **Affected organizations**: <list if determinable from Honeybadger>
- **Affected feature**: <which part of the app>

### Duration
- **Bug introduced**: <date> (commit <sha>)
- **First occurrence**: <date>
- **Last occurrence**: <date>
- **Exposure window**: <X days/hours>
- **Fix status**: <deployed/pending>

### Data Impact (theoretical — run diagnostic to confirm)
- **Nature of damage**: <corrupted/lost/duplicated/skipped side effects>
- **Models affected**: <ModelName>
- **External systems**: <affected/not affected>
- **Details**: <specific description of what went wrong with the data>

### Remediation Required
- [ ] <specific remediation action 1>
- [ ] <specific remediation action 2>
- [ ] <notify affected users? yes/no and why>
```

### Step 11: Get User Confirmation

Ask the user to confirm:
1. Whether the impact assessment looks accurate
2. Whether they want to proceed with committing the scripts
3. Whether any additional remediation is needed (e.g., user notification, Stripe adjustments)

**Do NOT proceed to Phase 6 without user confirmation.**

## Phase 6: Commit & Update PR

### Step 12: Add Scripts to the PR

If this skill is being run alongside `/fix-honeybadger` (worktree exists):

```bash
cd $WORKTREE_DIR
git add lib/tasks/diagnose_<short_description>.rake lib/tasks/remediate_<short_description>.rake
git commit -m "$(cat <<'EOF'
Add diagnostic and remediation scripts for Honeybadger fault #<fault_id>

Diagnostic: Identifies <ModelName> records affected during the exposure
window (<start_date> to <end_date>). Outputs JSON to stdout.

Remediation: Accepts diagnostic JSON as input and fixes affected records.
Dry-run by default.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

If this is a standalone run (no worktree), stage and commit normally.

### Step 13: Update the PR Description

If a PR already exists, update its description to include the impact assessment and run instructions:

```bash
gh pr edit <pr_number> --body "$(cat <<'EOF'
<existing PR body>

## Impact Assessment

### Scope
- **Total occurrences**: <count>
- **Affected users**: <count>
- **Exposure window**: <duration>

### Data Remediation

Two rake tasks are included for data remediation:

**Step 1: Diagnose** — Run in production to identify affected records:
```bash
bundle exec rake data:diagnose_<short_description> > diagnosis.json
```

Review the output:
```bash
cat diagnosis.json | python3 -m json.tool
```

**Step 2: Remediate (dry-run)** — See what would be fixed:
```bash
bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json
```

**Step 3: Remediate (apply)** — Fix the affected records:
```bash
bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json DRY_RUN=false
```

### Post-Deploy Checklist
- [ ] Deploy the code fix
- [ ] Run diagnostic script in production: `bundle exec rake data:diagnose_<short_description> > diagnosis.json`
- [ ] Review `diagnosis.json` — confirm affected records look correct
- [ ] Run remediation in dry-run: `bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json`
- [ ] Review dry-run output
- [ ] Run remediation for real: `bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json DRY_RUN=false`
- [ ] Verify affected records are corrected
- [ ] Monitor Honeybadger for recurrence
EOF
)"
```

## Phase 7: Final Report

### Step 14: Present Summary

```
## Impact Assessment Complete

### Fault: Honeybadger #<fault_id> — <ErrorClass>

### Impact (from Honeybadger)
- **Users affected**: <count>
- **Exposure window**: <duration> (<start> to <end>)

### Deliverables
- Diagnostic script: `lib/tasks/diagnose_<short_description>.rake`
- Remediation script: `lib/tasks/remediate_<short_description>.rake`
- PR updated with impact assessment and post-deploy checklist

### Post-Deploy Instructions
1. Deploy the fix
2. Run diagnostic: `bundle exec rake data:diagnose_<short_description> > diagnosis.json`
3. Review `diagnosis.json`
4. Dry-run remediation: `bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json`
5. Apply remediation: `bundle exec rake data:remediate_<short_description> INPUT=diagnosis.json DRY_RUN=false`
6. Monitor Honeybadger for 24 hours
```

## Important Guidelines

1. **Never modify production data directly** — always use a rake task that can be reviewed and audited
2. **Two-script pattern** — diagnostic script reads and outputs JSON; remediation script consumes that JSON
3. **Diagnostic script is read-only** — it must never write to the database
4. **Remediation script is input-driven** — it only fixes records listed in the diagnostic output, never queries independently
5. **Dry-run by default** — the remediation task must be safe to run without `DRY_RUN=false`
6. **Idempotency** — both scripts must be safe to run multiple times
7. **Ask before proceeding** — always get user confirmation before committing scripts
8. **Tenant awareness** — use `ActsAsTenant.without_tenant` in diagnostic, `ActsAsTenant.with_tenant` per-record in remediation
9. **PHI sensitivity** — script output should include record IDs but minimize PHI (no client names, DOBs, etc.)
10. **No silent failures** — log every record examined, every change made, and every error encountered
11. **stderr for status, stdout for data** — diagnostic script sends progress to `$stderr`, JSON to `$stdout`

## When No Data Remediation Is Needed

If the bug only caused errors (e.g., 500 pages, failed loads) without corrupting data:

1. Complete Phases 1-2 (Honeybadger data + damage assessment)
2. Note "No data remediation required — bug caused user-facing errors only, no data corruption"
3. Skip Phases 3-4 (no scripts needed)
4. Still update the PR with the impact assessment for the record
