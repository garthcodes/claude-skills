# Stedi Payer Directory ↔ the app's payer tables

How Stedi's payer directory is shaped, how each field lands in the app's `payers` /
`payer_groups` / `user_payer_groups` tables, and the procedure for answering
"which payers does contract X cover?" or "where does the name on this card
route?". Verified against the live directory on 2026-09-03 — re-verify field
names with a real request before relying on them; Stedi adds fields over time.

Companion script: `../scripts/stedi_payer_family.py` (read-only, test key is
fine, no production access needed).

## 1. The directory API

Base `https://healthcare.us.stedi.com/2024-04-01`, header `Authorization: Key <key>`.
The directory is **shared between test and production keys**, so use
`STEDI_TEST_API_KEY` from the checkout's `.env` — never a prod key, never a Fly
command, for a directory lookup.

| Call | Notes |
|---|---|
| `GET /payers/search?query=<text>&pageSize=N` | Matches `displayName`, `names[]`, `aliases[]`, `primaryPayerId`. **`pageSize` must be 10–100** (anything smaller is a 400). EAP payers only surface for a NAME query, never for the carrier's medical ID. |
| `GET /payers?pageSize=100&pageToken=<t>` | Whole directory (~3,700 payers, ~37 pages, `nextPageToken`). Items are bare payer objects (search wraps them in `{payer, score, matches}`). |
| `?parentPayerGroupId=…` on either | **Silently ignored** — there is no server-side family filter and no `/payer-groups` endpoint (404). Filter client-side over the full list; the script caches it for a day. |

Docs: `https://www.stedi.com/docs/healthcare/supported-payers` and the API
reference under `https://www.stedi.com/docs/healthcare/api-reference/` — WebFetch
before asserting a field exists.

## 2. Record shape (fields that matter to the app)

```json
{
  "stediId": "QSOCK",
  "displayName": "Surest",
  "primaryPayerId": "25463",
  "aliases": ["00229", "14407", "2007", "25463", "8139", "BIND"],
  "names": ["Bind"],
  "parentPayerGroupId": "FIVMG",
  "parentPayerGroupName": "UnitedHealth Group",
  "coverageTypes": ["dental", "medical", "vision"],
  "operatingStates": ["NATIONAL"],
  "programs": ["COMMERCIAL"],
  "transactionSupport": {
    "eligibilityCheck": "SUPPORTED",
    "claimStatus": "NOT_SUPPORTED",
    "professionalClaimSubmission": "SUPPORTED",
    "claimPayment": "ENROLLMENT_REQUIRED",
    "coordinationOfBenefits": "NOT_SUPPORTED"
  },
  "enrollment": {"ptanRequired": false, "transactionEnrollmentProcesses": {"claimPayment": {"type": "ONE_CLICK", "timeframe": "WEEKS"}}}
}
```

Three different "which payer is this" signals, and they answer different questions:

- **`parentPayerGroupId` / `parentPayerGroupName`** — corporate family. Sibling
  payers each have their **own** `primaryPayerId` and must be their own
  `Payer` row (UnitedHealthcare 87726, UMR 39026, Surest 25463, All Savers 81400
  are four rows). Only ~10% of payers carry a group (376 of 3,668); many Blue plans and
  state Medicare contractors have none. Not every family member is billable under one
  contract — see §5.
- **`names[]`** — brand names that route to **this same** `primaryPayerId`.
  UnitedHealthcare 87726 lists "Rocky Mountain Health Plans", "United Behavioral
  Health", "Optum UnitedHealth Behavioral Solutions", "Harvard Pilgrim Passport
  Connect", "UnitedHealthcare West". These are NOT separate rows — they are the
  card names that mean "bill 87726". This is the list to consult when a client
  or a legacy-system export says a name the app does not have.
- **`aliases[]`** — alternate routing IDs (other clearinghouses' IDs, legacy IDs,
  what appears in ERAs). Same payer, different ID strings.

`transactionSupport` keys: ERA support is **`claimPayment`**, not
`claimPaymentAdvice`. `ENROLLMENT_REQUIRED` means the transaction works only after
a Stedi enrollment is approved for the practice's NPI/TIN.

## 3. Field mapping → the app

The app's tables: `payers` (global, one row **per state**, not tenant-scoped),
`payer_groups` (curated carrier family, no state, one optional parent level for
EAP product lines), `user_payer_groups` (therapist × payer_group × state = "holds
this contract"). Schema in `db/schema.rb`; models `app/models/payer.rb`,
`payer_group.rb`, `user_payer_group.rb`.

| Stedi field | App column | Rule |
|---|---|---|
| `primaryPayerId` | `payers.edi_payer_id` | Sent as `tradingPartnerServiceId` on 837P (`claim_client.rb`) and 276 (`claim_status_client.rb`); `supports_electronic_claims?` requires it; ERA match tries it first. |
| `primaryPayerId` | `payers.clearinghouse_payer_id` | Sent as `tradingPartnerServiceId` on 270 (`eligibility_client.rb`). Same value as `edi_payer_id` for every medical row; **NULL on EAP rows** (no 270 is ever built for EAP). |
| `primaryPayerId` | `payers.primary_payer_id` | Informational copy; seeds set all three. |
| `stediId` | `payers.stedi_id` | Canonical adoption key. Unique per `(stedi_id, state_id)` — so a NATIONAL payer legitimately has one row per operating state with the same `stedi_id`. **Leave NULL** on a row that shares a carrier's trading partner (Optum EAP, Cigna EAP) or the index rejects it. `stedi_sourced?` is `stedi_id.present?`. |
| `aliases[]` | `payers.stedi_aliases` (jsonb array) | Used ONLY by `IngestEraService#find_payer` as the fallback after `edi_payer_id` (case-insensitive element match, `.order(:id).first`). NOT searched by the policy autocomplete, NOT consulted by eligibility, NOT editable in Avo (console/seed only). Keep an EAP row's aliases empty or it can steal the carrier's ERAs. |
| `displayName` | `payers.name` | Unique per `(name, state_id)`. The app may use its own curated name (e.g. "UnitedHealthcare"). |
| `names[]` | *(no column)* | Candidate `abbreviation` / search terms. Nothing in the app stores or searches these today — a gap worth knowing when a card name "doesn't exist". |
| `parentPayerGroupId/Name` | *(no column)* → `payers.payer_group_id` by hand | The app's `PayerGroup.name` is a **curated** family name ("UnitedHealthcare"), Stedi's is corporate ("UnitedHealth Group"). No stored link; use the correspondence table in §6 and set `payer_group` explicitly. Never let `PayerGroup.resolve_or_create` invent a group from a Stedi name — that creates an `auto_created` single-member group no therapist is credentialed with. |
| `operatingStates[]` | fan-out to `state_id` rows | `NATIONAL` or empty list → one row per state the practice operates in. Explicit list → only the listed states the practice operates in; a payer listing none of them (Oxford = CT/NJ/NY) should not be added. |
| `programs[]` | `payers.payer_type` enum | COMMERCIAL→`commercial`, MEDICARE→`medicare`, MEDICAID→`medicaid`; Blue plans → `blue_cross` by name (drives the 837P claim filing code `BL`). Often empty — fall back to the name. |
| `coverageTypes[]` | *(filter)* | Must include `medical`. Dental/vision-only rows are noise for a therapy practice. |
| `transactionSupport.professionalClaimSubmission` | `payers.electronic_claims_enabled` | `SUPPORTED` → true. `ENROLLMENT_REQUIRED` → false **until** the enrollment is approved (state Medicare Part B contractors are the standing example). `ValidateClaimService` blocks a claim when enabled but `edi_payer_id` is blank. |
| `transactionSupport.claimPayment` | `payers.era_enabled` | `SUPPORTED` → true; `ENROLLMENT_REQUIRED` → decide per enrollment status. |
| `transactionSupport.eligibilityCheck` | *(no column)* | Whether a 270 will work. EAP rows have `eap: true` and skip eligibility entirely. |
| `enrollment.*` | `payers.submission_requirements["stedi_enrollment"]` | Seed convention; merged, never replaced, so curated `telehealth_pos` / `eap_modifier` keys survive. |

## 4. Where the app resolves a payer, and what each path can see

Know this before deciding whether adding a row is enough:

| Path | What it matches on | Blind spot |
|---|---|---|
| Insurance-policy autocomplete (staff + client portal), `Api::PayersController` via `PayerSearchFieldComponent` | `name ILIKE` or `edi_payer_id ILIKE`, active rows, all states (a state prefix in the name is the only state cue) | Ignores `stedi_aliases`; the dropdown never renders the EDI ID (JS reads `payer.payer_id`, API sends `edi_payer_id`). Staff pick on brand name alone. |
| Scheduler payer filter, `AppointmentSchedulerComponent` | Groups, then flat `Payer#display_name` rows | — |
| Therapist credentialing picker, `PayerGroup.hierarchical_options` | `PayerGroup` rows (parent → indented EAP child) | Contract coverage is by group + state (`UserPayerGroup.for_payer`). A payer under the wrong group matches nobody. |
| ERA ingest, `IngestEraService#find_payer` | `edi_payer_id` → any `stedi_aliases` element → name/abbreviation | Ambiguity across state rows resolved by lowest id. |
| Legacy-system import (if the app has one), e.g. an importer's `find_or_create_payer` | `clearinghouse_payer_id` + client state, nothing else | Any miss (name only, or an ID not on a row) **creates** a new `Payer` with no EDI ID under a new `auto_created` group → cannot claim, cannot check eligibility, matches no therapist. |
| Eligibility 271 parse, `Stedi::EligibilityClient` | — | Never reads the 271 payer name; a wrong-payer AAA 75 is mapped to "check the member ID" (`eligibility_checks_helper.rb`). Eligibility will not tell you the policy is on the wrong row. |

Production payers are **hand-curated** (record the adopted list in a billing
playbook doc). A bulk directory sync imports every payer in the operating states,
most of which no therapist is credentialed with — prefer curation;
`db/seeds/payers.rb` is a literal dev/test list that does not seed prod. Adding or fixing a prod payer is a deliberate console change.

## 5. Procedure: "which payers does a carrier contract cover?"

1. **Anchor**: `stedi_payer_family.py --like "<known member or card name>"` → note
   `parentPayerGroupId`. If the name lands in another payer's `names[]`, the
   answer is "that existing row", not a new one.
2. **Enumerate**: `stedi_payer_family.py --group-id <id> --medical --claims-supported`
   (filters to `--states` plus NATIONAL). Add `--json` to keep the raw fields.
3. **Cut corporate ≠ contract.** Stedi's group is ownership. A commercial /
   behavioral-network contract normally covers the commercial plans and TPAs
   (`programs` COMMERCIAL or blank). Treat separately: `MEDICAID` rows (state
   Medicaid contract), `MEDICARE` / Medicare Advantage rows (only if
   the contract names MA), `VETERANS_AFFAIRS` (separate network), dental/vision,
   and physical-health / hospital / county networks that happen to share the
   parent. **Confirm the final list against the payer's participation letter or
   provider-relations rep** — the directory cannot tell you what was signed.
4. **Diff against the app**: for the target `PayerGroup`, list existing rows by
   `stedi_id` and `edi_payer_id` (prod reads need the user's approval per
   `CLAUDE.md` production rules). Re-verify existing rows' `primaryPayerId` too —
   Stedi re-parents and re-IDs payers (e.g. Meritain's primary moved from 64157
   to 41124; 64157 is now an alias).
5. **Add rows** (prod: a reviewed transactional runner script the user
   runs, dry run first; dev: `db/seeds/payers.rb` + `payer_groups.rb`
   for parity). Per row: `name`, `abbreviation`, `state`, **existing**
   `payer_group`, `payer_type`, `edi_payer_id` = `clearinghouse_payer_id` =
   `primary_payer_id` = `primaryPayerId`, `stedi_id`, `stedi_aliases` = `aliases`,
   `electronic_claims_enabled` / `era_enabled` from `transactionSupport`,
   `timely_filing_days`, `submission_requirements["stedi_enrollment"]`. One row per
   operating state. Wrap in a transaction and print the before/after count.
6. **Verify**: policy autocomplete finds the new name; `UserPayerGroup.for_payer`
   returns the credentialed therapists; an ERA carrying any alias would resolve
   to it; the billing playbook's payer table updated.

Adjacent risks to record (not fix) when you touch this area: autocomplete does
not search aliases or show the EDI ID; importer mints orphan payers on a name
miss; 271 payer name is never compared to the selected payer.

## 6. Example correspondences (Stedi directory, verified 2026-09-03)

Family data from the public directory, as a starting point — which members a
practice adopts depends on its contracts and states. Re-verify IDs before use.

| Stedi group | id | Curated `PayerGroup` | Family members (primaryPayerId `stediId`) |
|---|---|---|---|
| UnitedHealth Group | `FIVMG` | UnitedHealthcare | UnitedHealthcare 87726 `KMQTZ`, UMR 39026 `UWTOI`, Surest 25463 `QSOCK`, All Savers 81400 `AFLEJ`, Golden Rule 37602 `INRAO`, Student Resources 74227 `WVPHC`, UHC West 95959 `YEJAS`, Oxford 06111 `CYRGF` (CT/NJ/NY). Usually separate contracts: AARP/UHC MA 36273, UHC Community Plan (Medicaid), VA CCN, Optum IPAs, vision. Optum EAP has **no** directory entry (routes on 87726, `stedi_id` NULL). `names[]` on 87726 covers Rocky Mountain Health Plans, United Behavioral Health, Optum BH. |
| Aetna (CVS Group) | `IWQUE` | Aetna (+ child Aetna EAP) | Aetna 60054 `HPQRS`, Meritain Health **41124** `NPFPE` (64157 is now an alias), Aetna EAP EAP20 `LTVUZ`. Usually separate: Aetna Better Health (Medicaid), senior/dental. |
| Cigna | `BDKOJ` | Cigna (+ child Cigna EAP) | Cigna 62308 `HGJLR` (Cigna/Evernorth *Behavioral* Health routes here), GWH-Cigna 80705 `UNLEM`. Evernorth 62350 `VZFBY` has no Stedi group. Cigna EAP has no directory entry. |
| Anthem | `VJLBL` | Blue Cross Blue Shield (+ child Anthem EAP) | State Anthem BCBS plans, Anthem EAP ANTHMEAP `XQFDU`. Usually separate: Blue Medicare Advantage, Amerigroup, CareMore, Medicaid plans. |
| *(none)* | — | Blue Cross Blue Shield | Many independent Blue plans carry no parent group. BlueCard / FEP members bill to the local Blue row. |
| *(none)* | — | Medicare | State Part B contractors (e.g. Noridian, Novitas) carry no group; 837P is ENROLLMENT_REQUIRED → `electronic_claims_enabled: false` until enrolled; PTAN required. |

Update this table (or the playbook) when a new family is adopted.
