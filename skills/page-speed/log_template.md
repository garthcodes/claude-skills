# Page Performance Log

Maintained by `/page-speed`. Production Rails Pulse, successful GETs, ms, **app-wide stall minutes excluded**. Rails Pulse keeps 30 days; this file is the long-term record.

Rotation: a page worked in the last 14 days rests · `spike` pages rest 14 days · declined pages carry a `skip until` date.
Status: `in progress` → `shipped` (merged, waiting for data) → `measured` · `spike` · `skip until YYYY-MM-DD` · `watch` (noted, not worked)

## Roster

Before/After: stall-free `p50 / p95 · queries per load`. Queries per load is the fairer comparison, because p50 drifts as traffic and data grow.

| Page | Status | Last worked | Before p50 / p95 · q | After p50 / p95 · q | PR |
|---|---|---|---|---|---|

## Shared

Costs that appear on 5+ pages (`shared_ops.sql`). Fixing one speeds up all of them. Same statuses as the roster.

| Cost | Where | Pages | Before ms · per load | After ms · per load | Status | PR |
|---|---|---|---|---|---|---|

## Trend

7-day window, one row per date (a second run the same day replaces it). Excess wait = seconds spent waiting beyond 300 ms, summed over all page loads.

| Date | Page loads | p50 | p95 | Pages p95 > 1 s | Excess wait | Stall min |
|---|---|---|---|---|---|---|

## Runs

<!-- Newest first. Four lines max, one sentence each:
### MM/DD/YYYY · controller#action
- **Why:** … · **Cause:** …
- **Shipped:** … · **Declined:** …
- **PR:** #… · **Expected:** …
- **Noticed:** … (optional)
-->
