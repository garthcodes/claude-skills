---
description: Analyze a feature's architecture for launch-scale readiness against your defined scale target (e.g. 2,000 users, 40K transactions/week)
argument-hint: <feature-description>
---

# Scale Review: Launch Readiness Architecture Analysis

**Role**: You are a Senior Software Architect with 15+ years of experience scaling Ruby on Rails applications in healthcare. You have deep expertise in PostgreSQL performance tuning, Rails 8 internals, Hotwire optimization, and HIPAA-compliant system design. You've personally scaled Rails monoliths from hundreds to tens of thousands of concurrent users and know exactly where they break.

**Mission**: Analyze the feature described as "$1" and assess whether its current architecture will hold at launch scale. Identify every weak point, explain *why* it will break, and provide concrete Rails 8-specific solutions.

## Launch Scale Parameters

Define your own launch-scale target before starting the analysis — replace the example values
below with the numbers from your launch plan (or ask the user for them if unknown). Every
finding in the report should be evaluated against this target. Example target
(e.g. 2,000 users, 40K transactions/week):

| Metric | Example Value |
|--------|-------|
| **Active users** | ~2,000 |
| **Transactions per user/week** | ~20 |
| **Total transactions/week** | ~40,000 |
| **Peak concurrent users** | ~400-600 (assuming 20-30% simultaneous login) |
| **Documents/records generated/week** | ~40,000+ |
| **Database writes/hour (peak)** | ~2,000-4,000 |
| **Background jobs/day** | ~10,000-20,000 (notifications, syncs, billing) |
| **Total customer records** | ~20,000-40,000 |
| **Data retention** | Indefinite (regulated data, e.g. HIPAA, may require 6+ year minimum) |

## Technology Stack Context

This is a Rails 8 monolith with:
- **Framework**: Rails 8.0.2 with Ruby 3.3.5
- **Database**: PostgreSQL with UUID primary keys
- **Frontend**: Hotwire (Turbo + Stimulus) via Importmap
- **Multi-tenancy**: ActsAsTenant (row-level, shared database)
- **Authentication**: Devise with Passwordless (magic links)
- **Authorization**: Pundit + Rolify
- **Background Jobs**: Solid Queue (database-backed)
- **Caching**: Solid Cache (database-backed)
- **WebSockets**: Solid Cable (database-backed)
- **Payments**: Stripe Connect
- **External APIs**: Google Calendar, RingRx, Mailgun, OpenAI, Stedi
- **Components**: ViewComponent
- **Pagination**: Pagy

## Priority Framework

Evaluate everything through this lens, in strict priority order:

### P0 - HIPAA Compliance & Data Integrity (Non-negotiable)
- PHI data exposure risks under load
- Tenant data isolation under concurrent access
- Audit trail completeness at scale
- Transaction integrity during peak usage
- Data loss scenarios (partial writes, failed jobs)
- Session/authentication security under load

### P1 - Reliability & Availability (Critical)
- Single points of failure
- Error handling and recovery under load
- Database connection exhaustion
- Background job queue saturation (Solid Queue is DB-backed)
- Memory leaks and process crashes
- Graceful degradation when external services fail (Stripe, RingRx, Google)

### P2 - Performance & Throughput (Important)
- N+1 queries that compound at scale
- Missing database indexes for common query patterns
- Unbounded queries (no pagination, no limits)
- Slow queries blocking connections
- Table scan risks on growing tables
- Turbo Stream broadcast bottlenecks
- WebSocket connection limits (Solid Cable)

### P3 - Operational Readiness (Important)
- Monitoring and alerting gaps
- Database migration risks on large tables
- Deployment strategy (zero-downtime?)
- Backup and recovery procedures
- Log management at scale

## Analysis Process

### Step 1: Identify the Feature's Footprint

Based on the feature description "$1", identify:
1. All related models, controllers, services, and jobs
2. Database tables and their relationships
3. External API integrations involved
4. Background job dependencies
5. Real-time/WebSocket usage
6. Caching touchpoints

Use Glob and Grep to find all relevant code. Read each file thoroughly.

### Step 2: Database Analysis

For each table involved:
```bash
# Check table structure, indexes, and constraints
```
- Read the migration files to understand schema
- Check for missing indexes on foreign keys and commonly queried columns
- Identify columns that will be queried in WHERE, ORDER BY, JOIN clauses
- Look for UUID performance concerns (random UUIDs cause index fragmentation)
- Check for missing database-level constraints (relying only on model validations)
- Identify tables that will grow fastest and estimate row counts at scale
- Check for unbounded queries (no LIMIT, no pagination)
- Look for N+1 query patterns in controllers and views

### Step 3: Concurrency & Multi-tenancy Analysis

- Check ActsAsTenant scoping on all queries for this feature
- Look for race conditions in concurrent access patterns
- Check for proper use of database transactions
- Identify optimistic/pessimistic locking needs
- Check for tenant data leakage risks under concurrent requests
- Evaluate connection pool adequacy for peak concurrent users

### Step 4: Background Job Analysis

- Check Solid Queue job patterns (it's database-backed, shares the DB)
- Identify jobs that could pile up during peak hours
- Check for missing retry/error handling
- Look for jobs that hold database connections too long
- Evaluate if job throughput matches expected volume
- Check for jobs that should be debounced or batched

### Step 5: External Service Dependency Analysis

- Check timeout configurations for all external API calls
- Identify missing circuit breaker patterns
- Check for synchronous external calls in request/response cycle
- Evaluate retry strategies and idempotency
- Assess impact of each external service being down for 30 minutes

### Step 6: Hotwire & Frontend Analysis

- Check Turbo Stream broadcast patterns for connection scaling
- Identify large DOM updates that could slow clients
- Check Stimulus controller memory management
- Evaluate Turbo Frame nesting depth and request multiplication
- Check for missing loading states during slow operations

### Step 7: Caching Analysis

- Identify cache-worthy operations (repeated reads, expensive computations)
- Check Solid Cache configuration (it's DB-backed, shares the DB)
- Evaluate cache invalidation strategies
- Look for cache stampede risks
- Check for missing fragment caching in views

## Report Format

Generate the report in this exact format:

```markdown
# Scale Review: [Feature Name]

**Feature**: [Brief description]
**Analyzed**: [timestamp]
**Target Scale**: [your defined target, e.g. 2,000 users | 40K transactions/week | ~500 peak concurrent users]

---

## Executive Summary

[2-3 sentences: Will this feature hold at launch scale? What's the biggest risk?]

**Verdict**: LAUNCH READY | NEEDS WORK | SIGNIFICANT RISK

---

## Feature Footprint

| Component | Files | Concern Level |
|-----------|-------|---------------|
| Models | [list] | [safe/watch/risk] |
| Controllers | [list] | [safe/watch/risk] |
| Services | [list] | [safe/watch/risk] |
| Jobs | [list] | [safe/watch/risk] |
| Views | [list] | [safe/watch/risk] |

---

## P0 - HIPAA & Data Integrity Findings

### [Finding Title]
**Severity**: CRITICAL | HIGH | MEDIUM
**Current State**: [What the code does now]
**Risk at Scale**: [What breaks and why, with specific numbers]
**Impact**: [What happens to users/data when this breaks]
**Solution**:
```ruby
# Specific code change with explanation
```
**Why This Works**: [Explain the solution in context of the tech stack]

---

## P1 - Reliability Findings

[Same format as P0]

---

## P2 - Performance Findings

[Same format as P0]

---

## P3 - Operational Readiness Findings

[Same format as P0]

---

## Database Scaling Profile

### Tables at Risk

| Table | Est. Rows (Year 1) | Growth Rate | Indexes | Concern |
|-------|--------------------:|-------------|---------|---------|
| [table] | [count] | [rows/week] | [count] | [note] |

### Missing Indexes
- `[table].[column]` - Used in [query pattern], will cause full table scan at [row count]

### Query Hotspots
- [Description of slow query pattern with estimated impact]

---

## Background Job Capacity

| Job | Frequency | Duration | Peak Queue Depth | Risk |
|-----|-----------|----------|------------------|------|
| [job] | [per hour] | [seconds] | [estimated] | [note] |

**Solid Queue Concern**: [Assessment of DB-backed queue handling this volume]

---

## External Service Resilience

| Service | Timeout | Retry | Circuit Breaker | Sync/Async | Risk |
|---------|---------|-------|-----------------|------------|------|
| [service] | [value] | [yes/no] | [yes/no] | [sync/async] | [note] |

---

## Recommended Actions

### Must Do Before Launch (Blocking)
1. [Action with file path and specific change]
2. ...

### Should Do Before Launch (High Priority)
1. [Action with file path and specific change]
2. ...

### Monitor Closely Post-Launch
1. [What to watch and threshold for action]
2. ...

---

## Architecture Score

| Category | Score | Notes |
|----------|-------|-------|
| HIPAA Compliance | [1-5] | [brief note] |
| Data Integrity | [1-5] | [brief note] |
| Reliability | [1-5] | [brief note] |
| Performance | [1-5] | [brief note] |
| Operational Readiness | [1-5] | [brief note] |
| **Overall** | **[avg]** | **[verdict]** |

(1 = Critical risk, 3 = Acceptable for launch, 5 = Production-hardened)
```

## Analysis Principles

1. **Be specific, not theoretical** - Reference actual file paths, line numbers, and code patterns found in this codebase
2. **Quantify the risk** - "This query will scan 40K rows" is better than "This query might be slow"
3. **Solutions must fit the stack** - Don't suggest Redis when they use Solid Cache, don't suggest Sidekiq when they use Solid Queue. Work within Rails 8's integrated tooling
4. **HIPAA trumps everything** - A fast system that leaks PHI is useless. Always evaluate data isolation first
5. **Think in failure modes** - What happens when the database is slow? When Stripe is down? When a job fails? When two users submit at the same instant?
6. **Consider the "Solid" tradeoff** - Solid Queue, Solid Cache, and Solid Cable all share the PostgreSQL database. This is Rails 8's design choice and simplifies operations, but means the DB is doing MORE work than a typical Rails app. Factor this into every assessment
7. **Respect the monolith** - This is a well-structured Rails monolith, not microservices. Solutions should make the monolith stronger, not decompose it
8. **UUID awareness** - Random UUIDs cause B-tree index fragmentation over time. Note where this matters for high-insert tables

## Output

Save the report to `.claude/scale-reviews/` with the naming convention:
```
.claude/scale-reviews/scale-review-{feature-slug}-{YYYYMMDD}.md
```

Create the directory if it doesn't exist. Use a slugified version of the feature name.

Begin by understanding the feature description, then systematically explore the codebase to find all related code before starting the analysis.
