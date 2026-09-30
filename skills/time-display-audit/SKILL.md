---
description: Audit every place the app renders a date or time (views, components, helpers, mailers, SMS, portal messages, PDFs, CSV, JS, JSON) against the per-surface timezone and format rules, write a severity-ranked audit to .claude/audits/, then fix every finding in the same run and drive bin/ci to green. Does not commit.
argument-hint: [optional path scope, e.g. app/views/client_portal or app/components/foo_component.html.erb]
---

# Time Display Audit

You are a senior Rails engineer who has shipped scheduling software across US time zones and has been burned by every classic bug: the appointment reminder that says 2:00 PM when the session is at 1:00 PM because the mailer never left UTC, the invoice dated "tomorrow" because `created_at.strftime` ran on a UTC column after 5pm Phoenix, the Stimulus controller that formats a time in whatever zone the browser happens to be in, the CSV export that a biller reconciled against the wrong day. You know that in a therapy practice a wrong wall-clock time is not cosmetic — a client shows up an hour late, a no-show fee gets charged, a therapist double-books.

**Your mindset:**
- **Every timestamp in the database is a UTC instant** — no exceptions, no "office-local" columns, no formatted strings. A stored timestamp has no display zone until someone chooses one. Every render site must choose one **explicitly and correctly**; "it looked right on my machine" is a bug waiting for DST or a remote therapist.
- The zone is decided by **who is reading** and **what the time is tied to**, never by the server, the browser, or the developer's laptop.
- A `Date` column (`date_of_birth`, `service_date`) is a calendar day and needs no zone. A `datetime` column rendered as a date **does** need a zone — the day boundary moves.
- Consistency across surfaces is a correctness property: the same appointment must show the same wall-clock time on the therapist's calendar, in the client's portal, in the reminder SMS, and on the superbill.
- **Staff see the practice's clock.** Every staff surface renders in the **office's** zone — the appointment's office when the row is tied to one, otherwise the org's default office — so the calendar, the session's invoice, its note's `signed_at`, its reminder log, and the audit trail all read in the same clock, and two staff members looking at the same screen from different cities see the same numbers. A remote therapist reads the office clock (labelled `MST`), not their own.
- You fix root causes by routing sites through the shared helpers, not by sprinkling `in_time_zone` calls.

## Input

`$ARGUMENTS` is an optional path scope.

- **No argument:** audit the whole app — every directory in the Surface Map below.
- **Directory:** audit every file under it recursively.
- **File:** audit just that file.

Scope narrows the *inventory*, not the *rules* or the *verification*. A scoped run still writes the audit doc, still fixes, and still runs `bin/ci`.

## The Rules (the contract every site is judged against)

### Rule 1 — Zone is chosen by the audience (who is reading), never by the record

| Audience | Time is tied to… | Zone chain | Helper |
|---|---|---|---|
| **Client** (portal pages, client emails, SMS, system-posted portal messages, superbills, receipts, client-facing PDFs) | anything | client's stored zone → appointment's office → org default office → `Appointment::DEFAULT_TIMEZONE` | `ClientTimeHelper#client_strftime(time, client, format, appointment:)` |
| **Staff** — every staff surface: scheduling (calendar, appointment lists/cards/detail, availability, waitlist, therapist video lobby) **and** everything else (billing, invoices, claims, ERAs, ledger, audit logs, messaging timestamps, tasks, documents, signatures, admin, reports, CSV exports, staff emails) | anything | **appointment's office** (`Appointment#timezone`, when an appointment is in hand) → **org default office** → viewing staff user's `time_zone` (recipient `User` for mailers/SMS/jobs) → `Appointment::DEFAULT_TIMEZONE` | `StaffTimeHelper#staff_strftime(time, format, appointment:)` — pass `appointment:` whenever the record is tied to one (the appointment itself, its invoice, its note, its reminder log) so the record reads in the same clock as the calendar |

Rules of thumb for staff:
- There is **one** staff chain and it is **office-first**. The calendar shows the office's clock; so does everything derived from that appointment, and so does every other staff record via the org default office. Never resolve a staff zone from the *assigned therapist* or from the *viewer* ahead of the office — a therapist in Los Angeles reading the Phoenix calendar sees `2:00 PM MST`, same as the front desk does.
- The viewer's `time_zone` is a **fallback only**, reached when there is no appointment office and no org default office. It never overrides the office.
- Pass `appointment:` for any record that belongs to an appointment, not just for the appointment row itself — that is what keeps an invoice's `created_at` in the same clock as the session it bills. Records with no appointment (tasks, audit logs, messaging, admin) omit it and land on the org default office.
- The **scheduling vs. everything-else** distinction still exists, but only for **severity** (Phase 2): a wrong appointment time is P1, a wrong `created_at` on an invoice is P2. It never changes the zone chain.
- Avo admin (`app/avo/`) is staff.

### Rule 2 — Formats are named, not ad-hoc

Both helpers expose the same `FORMATS` table. Sites use a **named format key**; a raw strftime string at a call site is a finding unless it is one of the machine formats in Rule 5.

```
date:               %m/%d/%Y                      # CLAUDE.md mandate
long_date:          %B %d, %Y
short_date:         %b %d, %Y
weekday_long_date:  %A, %B %d, %Y
time:               %-l:%M %p %Z                  # "2:30 PM MST"
long_datetime:      %B %d, %Y at %-l:%M %p %Z
short_datetime:     %b %d at %-l:%M %p %Z
```

- Every **clock time** carries the zone abbreviation (`%Z`). No exceptions on either audience — a staff member reading a remote therapist's calendar needs it as much as a travelling client.
- Every **date** is `MM/DD/YYYY` unless a long form is deliberately chosen from the table. `%Y-%m-%d`, `%d/%m/%Y`, `%b %e` etc. are findings.
- If a site genuinely needs a format not in the table (e.g. a time range "2:00–2:50 PM MST"), **add a key to both helpers' `FORMATS`** rather than inlining a string. Keep the two tables identical.

### Rule 3 — Date-only rendering of a datetime column still needs a zone

`invoice.created_at.strftime("%m/%d/%Y")`, `appointment.start_time.to_date`, `Date.today`, `Time.now`, `.beginning_of_day` / `.end_of_day` / `.all_day` on a bare UTC value, `.to_date` before comparison with `Date.current` — all of these shift the calendar day for anything after ~5pm Phoenix. They are findings even though no clock time is shown. Route through `client_strftime(..., :date)` / `staff_strftime(..., :date)` or `in_client_zone` / `in_staff_zone` before `.to_date`.

True `Date` columns (`date_of_birth`, `service_date`, `dos`, `effective_date`, `due_date` when it is a `date` type in `db/schema.rb`) are exempt — check the column type in `db/schema.rb` before deciding.

### Rule 4 — JavaScript never picks the zone itself

Stimulus controllers and inline JS that format times must:
- receive the resolved IANA zone from the server via a `data-*-time-zone-value` attribute (resolved by the same helpers above), and
- format with `Intl.DateTimeFormat` / `toLocaleString(..., { timeZone })` passing that zone, with `timeZoneName: "short"` for clock times.

`new Date(x).toLocaleTimeString()` with no `timeZone` option, `getHours()`-style manual formatting, and Chart.js axis labels built from local `Date` parts are findings. Time inputs (`<input type="time">`) and their parse paths are covered by Rule 6, not this rule. JS that builds an instant to POST must send ISO 8601 **with an offset** (`toISOString()`), never a bare `YYYY-MM-DD HH:MM` string the server would parse as UTC.

### Rule 5 — Machine formats are exempt

Not findings:
- ISO 8601 / RFC 3339 with offset in JSON APIs, `datetime=` attributes on `<time>`, `data-*` attributes carrying instants, ICS feeds, Turbo Stream payloads consumed by JS that then applies Rule 4.
- Stripe, Stedi, RingRx, Google Calendar, Vertex request payloads (their format is dictated by the API).
- Log lines, Honeybadger context, filenames (`export_20260911.csv`), cache keys.
- `spec/` files — you update them when a fix changes behavior, but they are not audited.

### Rule 6 — Storage is UTC; parse in a zone, store an instant

Every `datetime`/`timestamp` column holds a UTC instant. This is guaranteed by `config.time_zone = "UTC"` and `config.active_record.default_timezone = :utc` in `config/application.rb` — as long as every value that reaches ActiveRecord is a zone-aware time. Findings under this rule:

- **Naive time construction** that produces a wall-clock value with no zone and lets Rails treat it as UTC: `Time.parse(...)`, `DateTime.parse(...)`, `Time.new(y, m, d, h, ...)` without an offset, `Time.local`, `Time.mktime`, `Date#to_time`, `"2026-03-15 14:00".to_time`. These silently store the wrong instant whenever the intended zone is not UTC. Fix: parse with `ActiveSupport::TimeZone[zone].parse(...)` / `Time.use_zone(zone) { Time.zone.parse(...) }` using the zone the form already resolves, so the value is a `TimeWithZone` and Rails stores its UTC instant.
- **Formatted times stored as strings** — a `string`/`text` column, JSONB key, or `metadata` hash holding `strftime` output or an ISO string *without* an offset. Instants belong in `datetime` columns; if the column type is wrong, record it under "Out of scope — schema" (never change `db/schema.rb`).
- **Wall-clock values stored as instants** — writing `in_time_zone(...)`-shifted values back to a column, or storing `.to_date` / `.beginning_of_day` of a local time into a `datetime` column. Storage never carries a display zone.
- **Config drift** — any change to `config.time_zone`, `config.active_record.default_timezone`, or a per-model `self.default_timezone`, `Time.zone =` assignment, or `ENV["TZ"]` in app code.

What stays **out of scope**: *which* zone a form parses in. Appointment forms display and parse wall-clock times in `appointment_form_time_zone` (office → therapist → current user); `AppointmentsController#adjust_appointment_times`, `AppointmentCreator#determine_appointment_timezone`, and `submitted_time_zone` decide that and you do not second-guess them. You may fix an input path that *loses* the zone (naive parse → wrong instant stored) and you may fix how a form *labels* the zone it displays; you never change the zone a correctly zone-aware parse uses. If you believe that choice is wrong, record it under "Out of scope — input paths" and move on.

### Rule 7 — Copy discipline still applies

Fixing a time format never adds help text, tooltips, or explanatory copy, and never strips copy you inherit. The zone abbreviation inside the formatted value is the only "explanation" a time gets.

## Surface Map

Directories to inventory when unscoped, with the audience each defaults to. A file's audience is decided by its path first, then overridden by content (a client-facing partial rendered from a staff controller is still client-facing).

| Path | Default audience |
|---|---|
| `app/views/client_portal/**`, `app/components/client_portal/**`, `app/views/onboarding/**`, `app/components/onboarding/**` | Client |
| `app/views/*_mailer/**` — mailers whose recipient is a client (`ClientMessageMailer`, `ReminderMailer` client actions, `PaymentMailer`, `CancellationFeeMailer`, `SuperbillMailer`, `MigrationAnnouncementMailer`) | Client |
| `app/views/*_mailer/**` — mailers whose recipient is staff (`UserMailer`, `PlatformBillingMailer`, `ConnectedAccountMailer`, staff reminder actions) | Staff (pass `appointment:` when the email is about one; `viewer:` = the recipient `User` for the fallback) |
| `app/services/text_message_service.rb`, `app/services/send_appointment_reminder_service.rb`, `app/services/personalize_message_service.rb`, any service that builds a message body or a system-posted portal message | Client (unless the recipient is a `User`) |
| `app/services/superbill/**`, `app/views/**/*.pdf.erb`, receipts, statements | Client |
| `app/views/appointments/**`, `app/views/calendar/**`, `app/components/appointment*/**`, `app/components/calendar*/**`, availability, waitlist, `app/views/video_meetings/**` (staff side) | Staff — scheduling (same chain; P1 severity) |
| Every other `app/views/**`, `app/components/**`, `app/helpers/**`, `app/avo/**` | Staff — everything else (same chain; P2 severity) |
| `app/javascript/**` | Follows the surface that mounts the controller |
| `app/controllers/**` — only flash messages and JSON that carry *formatted* strings | Follows the recipient |
| `app/models/**`, `app/jobs/**`, `app/services/**` — presenter-style methods that return formatted strings (`display_time`, `formatted_date`, `to_s` overrides) | Follows the caller; trace at least one caller to decide |

## Phase 0: Establish the helpers

Before inventorying, check whether `app/helpers/staff_time_helper.rb` exists.

If it does not, **create it first** as a mirror of `app/helpers/client_time_helper.rb` — same `extend self`, same `FORMATS` (copy the constant; do not reference the other module's so they can diverge deliberately later, but keep them identical today), same nil-safety — with:

```ruby
# app/helpers/staff_time_helper.rb
module StaffTimeHelper
  extend self
  FORMATS = { ... }.freeze   # identical to ClientTimeHelper::FORMATS

  # One office-first chain for every staff surface. Pass `appointment:` for any
  # record tied to an appointment so it reads in that appointment's office clock.
  # `viewer:` (defaults to Current.user; mailers/SMS/jobs pass the recipient) is
  # only reached when no office zone exists — it never overrides the office.
  def staff_time_zone(appointment: nil, viewer: Current.user)
    appointment&.timezone.presence ||               # appointment office -> org default
      Office.default_office&.timezone.presence ||
      viewer&.time_zone.presence ||
      Appointment::DEFAULT_TIMEZONE
  end

  def in_staff_zone(time, appointment: nil, viewer: Current.user)
  def staff_strftime(time, format, appointment: nil, viewer: Current.user)
end
```

Wire it exactly like `ClientTimeHelper` is wired on this branch: `include StaffTimeHelper` in `ApplicationComponent`, `helper StaffTimeHelper` in `ApplicationMailer`, and confirm `helper :all` picks it up for views. Then **fold the existing one-offs into it**: `ApplicationHelper#default_office_time_zone` / `#office_local_datetime` and `ApplicationComponent#default_office_time_zone` / `#office_local_date` become thin delegators (or are removed and their callers migrated) so there is exactly one staff zone chain in the codebase. Write `spec/helpers/staff_time_helper_spec.rb` covering every step of the chain (appointment office wins over org office; org office wins over the viewer even when the viewer has a zone; viewer wins over the default only when both offices are absent; explicit `viewer:` wins over `Current.user`), nil time, nil `Current.user`, and the `%Z` abbreviation.

If the helper already exists, read it and verify it matches the chain in Rule 1; fix it if it drifted.

## Phase 1: Inventory every render site

Build the inventory with greps, then read every hit in context. Do not trust the grep alone — the dangerous sites are the ones that don't say `strftime`.

```bash
# Explicit formatters
grep -rnE 'strftime|\.to_fs\(|to_formatted_s|\bl\(|I18n\.l\b|time_tag|time_ago_in_words|distance_of_time' app --include='*.rb' --include='*.erb'
# Silent day-shifters (Rule 3)
grep -rnE '\.to_date\b|Date\.today|Time\.now\b|\.beginning_of_day|\.end_of_day|\.all_day|\.to_s\(:' app --include='*.rb' --include='*.erb'
# Zone choices made inline (should be inside the helpers only)
grep -rnE 'in_time_zone|Time\.use_zone|Time\.zone\b|time_zone|timezone' app --include='*.rb' --include='*.erb'
# JavaScript
grep -rnE 'toLocale(Date|Time)?String|Intl\.DateTimeFormat|getHours\(|getMinutes\(|new Date\(' app/javascript
# JSON / API formatted strings
grep -rnE 'strftime|to_fs' app/controllers app/serializers 2>/dev/null
# Storage (Rule 6): naive parses/constructors that reach ActiveRecord, and formatted times written to columns
grep -rnE '\bTime\.parse\(|\bDateTime\.parse\(|\bTime\.new\([0-9]|\bTime\.local\(|\bTime\.mktime\(|\.to_time\b|Time\.zone\s*=|default_timezone|ENV\["TZ"\]' app --include='*.rb'
grep -rnE '(update|create|assign_attributes|\[:[a-z_]+_at\]\s*=|_at:\s*).*strftime' app --include='*.rb'
```

Then hunt the hits greps miss:
- Presenter/model methods that return formatted strings — grep `def (formatted|display|human|pretty)_` and `def .*_(date|time|at)_(string|text|label)`.
- `Superbill::Presenter` and any PDF template.
- ERB that interpolates a `TimeWithZone` with `<%= record.starts_at %>` and no formatter at all (renders the UTC default `to_s`). Grep `<%= [a-z_.]+(_at|_time|_on|starts_at|ends_at|start_time|end_time)\s*%>`.
- Every `FORMATS`-style constant or `DATE_FORMAT =` outside the two helpers.
- `config/locales/*.yml` `time:`/`date:` formats used via `l(...)`.
- Storage sites: every hit from the Rule 6 greps, plus `string`/`jsonb` columns whose name ends in `_at`/`_time`/`_on` in `db/schema.rb` (a `datetime` stored as text). Confirm `config/application.rb` still sets `config.time_zone = "UTC"` and `config.active_record.default_timezone = :utc` and record it under "Verified clean".

Record each site as: `path:line | audience | binding (appointment / none) | current zone source | current format | what is rendered`.

**Also record the existing helper call sites** (`client_strftime`, `office_local_datetime`, `office_local_date`) — they still get classified, because a correct helper called with the wrong audience is a finding.

## Phase 2: Classify every site

For each site decide the **required** zone and format from the Rules, compare with what the site does, and assign exactly one verdict:

| Verdict | Meaning |
|---|---|
| `OK` | Correct helper, correct audience, named format. |
| `RAW_UTC` | No zone conversion at all (`strftime` / `to_s` / `to_date` on the stored value). |
| `WRONG_ZONE` | Converts, but to the wrong chain for the audience (e.g. portal page using `office_local_datetime`; staff calendar using the *assigned therapist's* or the *viewer's* zone instead of the office's; an invoice for an appointment rendered without `appointment:` so it lands on the org office while the calendar shows a different office; hard-coded `"America/Phoenix"`). |
| `INLINE_ZONE` | Correct zone but resolved by hand at the call site (`in_time_zone(client.timezone)`) instead of via the helper — will drift. |
| `WRONG_FORMAT` | Date not `MM/DD/YYYY` or a raw strftime string where a named format exists. |
| `NO_ABBREV` | Clock time without `%Z`. |
| `JS_LOCAL` | JavaScript formats without a server-provided zone. |
| `NAIVE_STORE` | A value reaches the database as a naive time, a zone-shifted wall-clock, or a formatted string (Rule 6). The stored instant is wrong; every display of it is wrong regardless of helper. |
| `SKIP` | Exempt by Rule 5, a true `Date` column (Rule 3), or an input path (Rule 6). State which. |

A site can only carry one verdict; pick the most severe (top of the table wins) — except `NAIVE_STORE`, which outranks every display verdict because it corrupts the stored instant.

### Severity

- **P0** — The stored instant is wrong (`NAIVE_STORE`, any column), or a client-facing wall-clock time or day is wrong or can be wrong: `RAW_UTC` / `WRONG_ZONE` / `JS_LOCAL` on any Client-audience site, or on an appointment time anywhere. A client can miss a session.
- **P1** — Staff scheduling surface wrong or can be wrong: `RAW_UTC` / `WRONG_ZONE` / `JS_LOCAL` on staff scheduling. A therapist can double-book or miss a session.
- **P2** — Staff "everything else" `RAW_UTC` / `WRONG_ZONE` / `JS_LOCAL`, and any `INLINE_ZONE`. Wrong day on an invoice, ledger, or audit log — or a record that no longer lines up with its appointment on the calendar; drift risk.
- **P3** — `WRONG_FORMAT` / `NO_ABBREV`. Cosmetic today, inconsistent tomorrow.

## Phase 3: Write the audit document

Write `.claude/audits/time-display-audit.md` (append `-<scope-slug>` to the filename when `$ARGUMENTS` was given, e.g. `time-display-audit-client-portal.md`). Use the shape `/audit-fixer` consumes so a partial run can be resumed with it:

```markdown
# Audit: Time Display

*Created: MM/DD/YYYY • Scope: <branch> @ <short sha> • Path scope: <args or "whole app"> • Status: open, none fixed*

<one paragraph: how many sites inventoried, how many per verdict, the rules applied (link Rule numbers above by name)>

| # | Site | Audience | Verdict | Severity |
|---|------|----------|---------|----------|

## P0 — Stored instant or client-facing time can be wrong
### 1. <one-line defect>
`path:line`
**Renders:** what the user sees today, with a concrete example (UTC instant → what shows vs what should show).
**Required:** audience, zone chain, named format.
**Fix:** the exact helper call that replaces it, and any spec to update.

## P1 — Staff scheduling can be wrong
## P2 — Staff records / drift risk
## P3 — Format and abbreviation

## Verified clean
<sites that were `OK`, one line each — so the next run can diff>

## Out of scope — input paths
<Rule 6 observations about *which* zone a form parses in, if any>

## Out of scope — schema
<columns that hold times but are the wrong type (string/jsonb instead of datetime), for a separate migration ticket>

## Skipped
<`SKIP` sites grouped by reason>
```

Write the document **before** fixing anything. It is the checklist for Phase 4 and the record if the run is interrupted.

## Phase 4: Fix every finding

Work the audit top-down, P0 first, one finding at a time. For each:

1. Re-read the site in full context (the whole partial/component/method, and one caller if it is a presenter method).
2. Replace with the helper call named in the audit's **Fix:** line. Prefer `client_strftime` / `staff_strftime` with a named format. For a date-only render of a datetime column, use the `:date` key. For `.to_date` comparisons, convert with `in_client_zone` / `in_staff_zone` first. For a `NAIVE_STORE` site, replace the naive parse/constructor with a zone-aware one using the zone the surrounding code already resolves — the resulting `TimeWithZone` stores as UTC on its own; never add a manual `.utc` or offset arithmetic.
3. For components, the helper is already included via `ApplicationComponent`; for services/jobs call `ClientTimeHelper.client_strftime(...)` / `StaffTimeHelper.staff_strftime(..., appointment:, viewer: recipient_user)` module-style (there is no `Current.user` outside a request — pass `viewer:` for staff emails/SMS/jobs so the fallback still resolves); for JS add the `data-…-time-zone-value` attribute at the mount point (resolved with the helper) and pass it to `Intl.DateTimeFormat`.
4. Do not "fix" a `SKIP` site. Do not change which zone a form parses in (Rule 6, out of scope).
5. Find the specs that cover the file (`grep -rl "<basename or class>" spec/`) and update expectations that encoded the old behavior. If a client-facing site had **no** spec asserting the rendered zone, add one example that freezes time at an instant that crosses the day boundary (e.g. `2026-03-15 02:30:00 UTC` → `03/14/2026 7:30 PM MST` for Phoenix) so the regression is caught.
6. Mark the finding `✅ fixed` in the audit table immediately, so the doc always reflects state.

Batch mechanical P3 fixes (same pattern, many files) after the P0–P2 pass, but still one file at a time with a read before each edit.

Do not stop after the first finding. After each fix, check the audit table: if any row is not `✅ fixed` or `SKIP`, the next thing you do is the next fix. Only when every row is resolved do you go to Phase 5.

## Phase 5: Verify with bin/ci

Run the full suite exactly once the fixes are in, **one `bin/ci` at a time** (never in parallel with another worktree's CI — it saturates Postgres connections):

```bash
bin/ci
```

- **Lint** must be run through `bin/ci` or `bin/standardrb` — never bare `bundle exec standardrb` (it reformats `db/schema.rb` in worktrees).
- If a failure is caused by your change, fix it at the root (usually a spec asserting the old zone/format, or a factory with a naive time) and rerun `bin/ci`. Never loosen an assertion to `include("PM")` to get past it.
- If a failure is demonstrably pre-existing (reproduce it on a clean `git stash` of your changes, or it is in a file you never touched and unrelated to time), record it in the final report under "Pre-existing failures" and do not chase it.
- System-spec flakes: `rspec-retry` gives 3 attempts. A `RSpec::Retry: 2nd try` line on a spec you touched means your change made it timing-sensitive — look at it.

`bin/ci` must exit 0 (or exit non-zero only on recorded pre-existing failures) before you finish.

## Phase 6: Close out

1. Update the audit header: `Status: fixed MM/DD/YYYY — N/N findings applied, bin/ci green` (or the honest variant).
2. **Do not stage, commit, or push.** Leave the working tree dirty for the user to review.
3. Final report to the user, in this order:
   - Counts: sites inventoried, findings by severity, fixed, skipped.
   - The helper you created or changed and where it is wired.
   - Any Rule 6 input-path concerns you recorded but did not touch.
   - `bin/ci` outcome, with the exact output of any failure you left standing.
   - Path to the audit doc.

## Guardrails

- Never hard-code an IANA zone or abbreviation in app code. The only literal zones allowed are `Appointment::DEFAULT_TIMEZONE`, the `"UTC"` terminal fallback inside `StaffTimeHelper`, and spec fixtures.
- Never use `Time.use_zone` or set `Time.zone` around a render to "fix" a page — the portal compares against `Time.current` / `Date.current` in the same views and mailers/jobs have no request. Explicit helper calls only.
- Never change `db/schema.rb`, migrations, or column types. If a `datetime` column should really be a `date`, record it under "Out of scope" — it is a separate ticket.
- Never touch `config.time_zone` / `config.active_record.default_timezone` in `config/application.rb` — they are `"UTC"` / `:utc` and stay that way. The fix for a wrong-looking time is always at the render or parse site, never in config.
- Never write a zone-shifted or formatted time to the database. Storage is UTC instants only.
- Production is live. This skill never runs anything against it.
