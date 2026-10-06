# Slow-page patterns

Check the hot files against this list after `drilldown.sql`. Each row gives the cause, how it shows up in the drilldown, what to grep for, and the fix. Most of it comes from Nate Berkopec's speedshop.co posts (sources at the bottom). Operation types in the drilldown are Rails Pulse's: `sql`, `template`, `partial`, `layout`, `collection`, `cache_read`, `cache_write`, `http`, `job`, `mailer`, `storage`.

## ActiveRecord

| Cause | Drilldown shows | Grep the hot files for | Fix |
|---|---|---|---|
| `count` on a relation that is also rendered | a `SELECT COUNT(*)` next to the list's `SELECT` | `.count` in views/components | `.size`: it uses the loaded rows. Use `.load.size` if the count renders before the list |
| `present?` / `any?` / `exists?` and then iterate | `SELECT 1 … LIMIT 1` plus the full `SELECT`. `exists?` is never memoized, so it repeats | `.exists?`, `.any?`, `.empty?` right before `.each` | `.load.any?`: one query, and the rows are reused |
| Scope, `where`, or `order(…).first` inside a model instance method | the same `SELECT` with `reps` ≈ row count, **even though `includes` is there** | `where`/`order`/`first`/`find_by`/`sum`/`count` inside instance methods | a scoped association (`has_many :active_notes, -> { active }, class_name: …`), preloaded. Any instance method will end up called in a loop |
| Preload on the wrong association | an N+1 despite `includes` | compare `includes(…)` with what the view actually reads | preload the association the view reads |
| Role or policy checks for every row | Rolify `roles` SELECTs × rows | `policy(…)`, `has_role?`, `accessible_*` inside loops | memoize per user for the request (PR #419: `User` role names and accessible ids) |
| Math in Ruby over loaded rows | one large `SELECT`, then high non-SQL time | `.map(&:x).sum`, `.select { }` over relations | `sum`/`group`/`pluck` in SQL |

## Caching: last, not first

Remove the queries and work first. Only consider caching if rendering is still the main cost after that.

| Cause | Drilldown shows | Fix |
|---|---|---|
| Many small `Rails.cache.fetch` calls per row | many `cache_read` ops per load | one fragment per row, or collection caching (`render partial: …, collection: …, cached: true`) |
| Caching something cheap | `cache_read` ms ≥ the render it saves | remove it. Solid Cache is a database round trip, so don't cache anything that renders in under ~10–20 ms |
| A fragment that never hits | `cache_write` ≈ `cache_read` per load | the key changes on every request (a timestamp, the current user). Fix the key or drop the cache |

Fragment keys: use the record (`cache record`, which is key-based expiration on `updated_at` plus the template digest), and `touch: true` on `belongs_to` so a change to a child busts its parent.

## Work that isn't SQL or rendering

| Cause | Drilldown shows | Fix |
|---|---|---|
| External API on the request path | `http` ops | move to a job, or load it later with `turbo_frame_tag …, src:, loading: :lazy` |
| An inline job, mail or file build | `job` / `mailer` / `storage` ops, or one long `controller` span (`send_data`, WickedPdf, CSV) | `perform_later`; for downloads, build the file in a job and send a link |
| Large HTML | high `avg_kb` in the distribution section (>~200 KB is a lot of rendering) | paginate with Pagy, or put panels below the fold in a lazy Turbo Frame |
| Unexplained Ruby time (controller ms well above sql + view ms) | none of the above | profile it: see SKILL.md Step 3 |

## How speed fixes break pages

A speed fix must not change what the page shows or who can see it. These are the ways it usually does. The plan, the reviews, the bug hunt and the cold review all check the diff against this list.

| Fix | How it breaks | Check |
|---|---|---|
| `includes` + `where`/`references` on the association | becomes a JOIN: parents without children vanish, and the preloaded children are filtered | rows on the page before = after, including parents with no children |
| Ruby filter/sum moved into SQL | Ruby saw the default scope (`active`, tenant) and `Time.zone`; raw SQL, `unscoped` or `DATE(col)` (UTC) don't. `SUM` of nothing is `nil`, not `0` | soft-deleted rows, another org's rows, evening records in the practice's zone, empty sets |
| `pluck`, `select_all`, `find_by_sql` | skips model defaults, decryption, enums and `acts_as_tenant` when it's raw SQL | tenant and soft-delete conditions written out, or stay on the relation |
| `count` → `size`, `exists?` → `load.any?` | the loaded rows are a page, or were filtered in Ruby, so the number changes | totals and "no results" states |
| `distinct`, `group`, new `joins` | order changes; joins duplicate rows, which breaks pagination | order and row counts on page 1 and page 2 |
| Memoization | stored on a class, constant or cached object outlives the request and leaks between users or orgs; memoized `nil`/`false` recomputes | per-request instance only, keyed by user when it varies |
| Caching | key misses the tenant, role or a field that changes the output → stale or another user's data; PHI lands in Solid Cache | key covers everything the fragment reads; `touch: true` path busts it |
| Lazy Turbo Frame / pagination | content no longer in the first paint; links, anchors, print, system specs and screen readers that expected it break | the moved content still reachable, and its specs still pass |
| New index | unique index fails on existing prod duplicates; non-concurrent build locks a hot table | `algorithm: :concurrently`; duplicates counted through `bin/prod-sql` first |

## Reference points

- Healthy Rails: median under ~100 ms, p95 under 1 s. A server time under ~300 ms leaves room for a page to be visible within 1 s, which is why the skill's "worth doing" gate is p50 300 ms / p95 1 s.
- Power law: 80% or more of the wait sits in a few spots. Don't touch code under ~5% of a page's time, however slow it looks in isolation.
- Rails Pulse `duration` is time inside the app. Time a request spends waiting for a free Puma thread (2 workers × 5 threads in `fly.toml`) is not in it, so page code can't explain a stall where only the web machine slowed.

Sources: speedshop.co/blog: *3 ActiveRecord Mistakes*, *Complete Guide to Rails Caching*, *Why Your Rails App is Slow*, *Why Premature Optimization is Bad*, *AO3 Performance Audit*, *rack-mini-profiler*, *The Ruby GVL and Scaling*.
