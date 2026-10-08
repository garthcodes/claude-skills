# Page Performance Log

Maintained by `/page-speed`. Production Rails Pulse, successful GETs, ms, **app-wide stall minutes excluded**. Rails Pulse keeps 30 days; this file is the long-term record.

Rotation: a page worked in the last 14 days rests · `spike` pages rest 14 days · declined pages carry a `skip until` date.
Status: `in progress` → `shipped` (merged, waiting for data) → `measured` · `spike` · `skip until YYYY-MM-DD` · `watch` (noted, not worked)

## Roster

| Page | Status | Last worked | Before p50 / p95 | After p50 / p95 | PR |
|---|---|---|---|---|---|
| Calendar (`appointments#index`) | shipped | 09/22/2026 | 1140 / 3250 | | #212 |
| Client page (`clients#show`) | shipped | 09/24/2026 | 690 / 1580 | | #218 |
| Staff conversation (`staff/conversations#show`) | shipped | 09/25/2026 | 575 / 1720 | | #224 |
| Client list (`clients#index`) | shipped | 09/25/2026 | 440 / 810 | | #229 |

## Trend

7-day window at each run. Excess wait = seconds spent waiting beyond 300 ms, summed over all page loads.

| Date | Page loads | p50 | p95 | Pages p95 > 1 s | Excess wait | Stall min |
|---|---|---|---|---|---|---|
| 09/22/2026 | 2400 | 230 | 1340 | 7 | 410 | 1 |
| 09/24/2026 | 4100 | 220 | 1180 | 8 | 590 | 2 |
| 09/25/2026 | 5600 | 225 | 1120 | 10 | 860 | 2 |
| 09/25/2026 | 6800 | 230 | 1090 | 13 | 1050 | 2 |

## Runs

### 09/25/2026 · clients#index
- **Why:** most waiting among eligible pages (70 s / 14 d, 440 / 810 ms) while Calendar, Client page and Conversations rest · **Cause:** every row re-ran role lookups (Rolify queries each `has_role?`) and rebuilt the therapist's accessible-client list for `ClientPolicy#edit?` (~15 queries per row).
- **Shipped:** `User` memoizes global role names, accessible client ids and clinical supervisee ids per instance (cleared on add/remove role and `reload`), and `ClientPolicy` checks the memoized ids · **Declined:** none.
- **PR:** #229 · **Expected:** 0.43 s → ~0.27 s typical, and fewer role queries on every page; locally a therapist's 20-row list went from about 280 → 35 queries and ~800 → ~470 ms.
- **Noticed:** #212/#218/#224 not yet 3 days in production, so no After numbers yet (#212 measurable from 09/25 evening).

### 09/25/2026 · staff/conversations#show
- **Why:** 17% of loads over 1 s with ~200 ms of fixable SQL (35 s / 14 d; `clients#index` ranked just above at 37 s but is near fast at 340 / 860) · **Cause:** each message ran its own mention check, "has replies?" check, and thread-replies query (~65 trips, ~200 ms per load).
- **Shipped:** `Message.with_display_associations` preloads mentions and replies (with their own display associations) and the component reads them in memory · **Declined:** none.
- **PR:** #224 · **Expected:** 0.56 s → ~0.35 s typical; locally 3 → 12 messages went from ~45 → ~180 queries before, flat at ~12 after.
- **Noticed:** `SolidCable::TrimJob` runs inline on every conversation open (~60 ms); `clients#index` rows re-run policy/`accessible_clients` checks (~60 ms); #212 measurable from 09/25 evening, #218 from 09/27.

### 09/24/2026 · clients#show
- **Why:** second-most waiting in the app (140 s / 14 d, 28% of loads over 1 s) · **Cause:** every imported legacy-EHR document (about 50 typical, a few hundred at most per client, ~3 KB of HTML each) rendered inside a collapsed section; pages over 500 KB had a p50 of 1.18 s vs 0.58 s under 150 KB.
- **Shipped:** lazy Turbo Frame loads the imported-documents rows when the section is opened, and the unused clinical_documents/chart_notes preload is gone · **Declined:** none.
- **PR:** #218 · **Expected:** 0.70 s → ~0.5 s typical, heavy clients 1.2 s → ~0.6 s; locally 150 documents went from ~540 KB / 58 queries to ~120 KB / 55.
- **Noticed:** app-wide stall 09/24 morning (about 25 requests, worst ~5 s; jobs slowed too, no deploy → DB side); `accessible_clients` rebuilt ~14× per client-page load (~40 queries).

### 09/22/2026 · appointments#index
- **Why:** most waiting in the app (175 s / 14 d, 53% of loads over 1 s) · **Cause:** readiness icons re-fetched each client via an unpreloaded `identified_client` and recomputed readiness 3× per appointment (~320 queries, ~680 ms SQL per load).
- **Shipped:** preload `identified_client` with contacts/payment methods, and memoize readiness per client per render · **Declined:** none.
- **PR:** #212 · **Expected:** 1.1 s → ~0.4–0.5 s typical; local render of 8 appointments went from 165 to 51 queries.
- **Noticed:** app-wide stall 09/22 afternoon (about 20 requests, worst ~50 s; jobs normal, no deploy → web machine, not DB).

<!-- Newest first. Four lines max, one sentence each:
### MM/DD/YYYY · controller#action
- **Why:** … · **Cause:** …
- **Shipped:** … · **Declined:** …
- **PR:** #… · **Expected:** …
- **Noticed:** … (optional)
-->
