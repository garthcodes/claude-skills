# Page Performance Log

Maintained by `/page-speed`. Production Rails Pulse, successful GETs, ms, **app-wide stall minutes excluded**. Rails Pulse keeps 30 days; this file is the long-term record.

Rotation: a page worked in the last 14 days rests · `spike` pages rest 14 days · declined pages carry a `skip until` date.
Status: `in progress` → `shipped` (merged, waiting for data) → `measured` · `spike` · `skip until YYYY-MM-DD` · `watch` (noted, not worked)

## Roster

| Page | Status | Last worked | Before p50 / p95 | After p50 / p95 | PR |
|---|---|---|---|---|---|
| Calendar (`appointments#index`) | shipped | 09/22/2026 | 1099 / 3400 | | #380 |
| Client page (`clients#show`) | shipped | 09/24/2026 | 704 / 1621 | | #396 |
| Staff conversation (`staff/conversations#show`) | shipped | 09/25/2026 | 560 / 1781 | | #407 |
| Client list (`clients#index`) | shipped | 09/25/2026 | 429 / 794 | | #419 |

## Trend

7-day window at each run. Excess wait = seconds spent waiting beyond 300 ms, summed over all page loads.

| Date | Page loads | p50 | p95 | Pages p95 > 1 s | Excess wait | Stall min |
|---|---|---|---|---|---|---|
| 09/22/2026 | 2229 | 227 | 1369 | 7 | 393 | 1 |
| 09/24/2026 | 4265 | 214 | 1151 | 7 | 607 | 2 |
| 09/25/2026 | 5905 | 224 | 1138 | 11 | 892 | 2 |
| 09/25/2026 | 7000 | 229 | 1093 | 14 | 1100 | 2 |

## Runs

### 09/25/2026 · clients#index
- **Why:** most waiting among eligible pages (72 s / 14 d, 429 / 794 ms) while Calendar, Client page and Conversations rest · **Cause:** every row re-ran role lookups (Rolify queries each `has_role?`) and rebuilt the therapist's accessible-client list for `ClientPolicy#edit?` (~15 queries per row).
- **Shipped:** `User` memoizes global role names, accessible client ids and clinical supervisee ids per instance (cleared on add/remove role and `reload`), and `ClientPolicy` checks the memoized ids · **Declined:** none.
- **PR:** #419 · **Expected:** 0.43 s → ~0.27 s typical, and fewer role queries on every page; locally a therapist's 20-row list went from 283 → 33 queries and ~810 → ~470 ms.
- **Noticed:** #380/#396/#407 not yet 3 days in production, so no After numbers yet (#380 measurable from 09/25 10:36 PM MST).

### 09/25/2026 · staff/conversations#show
- **Why:** 17% of loads over 1 s with ~200 ms of fixable SQL (33 s / 14 d; `clients#index` ranked just above at 36 s but is near fast at 337 / 855) · **Cause:** each message ran its own mention check, "has replies?" check, and thread-replies query (~65 trips, ~200 ms per load).
- **Shipped:** `Message.with_display_associations` preloads mentions and replies (with their own display associations) and the component reads them in memory · **Declined:** none.
- **PR:** #407 · **Expected:** 0.56 s → ~0.35 s typical; locally 3 → 12 messages went from 47 → 181 queries before, flat at ~12 after.
- **Noticed:** `SolidCable::TrimJob` runs inline on every conversation open (~61 ms); `clients#index` rows re-run policy/`accessible_clients` checks (~60 ms); #380 measurable from 09/25 10:35 PM MST, #396 from 09/27.

### 09/24/2026 · clients#show
- **Why:** second-most waiting in the app (142 s / 14 d, 28% of loads over 1 s) · **Cause:** every imported legacy-EHR document (53 typical, up to 266 per client, ~3 KB of HTML each) rendered inside a collapsed section; pages over 500 KB had a p50 of 1.18 s vs 0.58 s under 150 KB.
- **Shipped:** lazy Turbo Frame loads the imported-documents rows when the section is opened, and the unused clinical_documents/chart_notes preload is gone · **Declined:** none.
- **PR:** #396 · **Expected:** 0.70 s → ~0.5 s typical, heavy clients 1.2 s → ~0.6 s; locally 155 documents went from 538 KB / 58 queries to 120 KB / 55.
- **Noticed:** app-wide stall 09/24 8:15 AM MST (25 requests, worst 4.8 s; jobs slowed too, no deploy → DB side); `accessible_clients` rebuilt ~14× per client-page load (~40 queries).

### 09/22/2026 · appointments#index
- **Why:** most waiting in the app (180 s / 14 d, 53% of loads over 1 s) · **Cause:** readiness icons re-fetched each client via an unpreloaded `identified_client` and recomputed readiness 3× per appointment (~320 queries, ~680 ms SQL per load).
- **Shipped:** preload `identified_client` with contacts/payment methods, and memoize readiness per client per render · **Declined:** none.
- **PR:** #380 · **Expected:** 1.1 s → ~0.4–0.5 s typical; local render of 8 appointments went from 165 to 51 queries.
- **Noticed:** app-wide stall 09/22 5:13 PM MST (18 requests, worst 50 s; jobs normal, no deploy → web machine, not DB).

<!-- Newest first. Four lines max, one sentence each:
### MM/DD/YYYY · controller#action
- **Why:** … · **Cause:** …
- **Shipped:** … · **Declined:** …
- **PR:** #… · **Expected:** …
- **Noticed:** … (optional)
-->
