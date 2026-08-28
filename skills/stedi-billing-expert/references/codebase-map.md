# Stedi Integration Codebase Map

Complete inventory of the Stedi clearinghouse integration in this repo. Verify paths still exist before citing them — this map is a starting index, not ground truth.

## Stedi API clients (`app/services/stedi/`)

| File | X12 / Stedi API | Notes |
|---|---|---|
| `base_client.rb` | Shared Faraday HTTP layer | Redis circuit breaker, `ApiError`/`AuthenticationError`/`RateLimitError`/`CircuitOpenError`, resolves `STEDI_TEST_API_KEY` vs `STEDI_API_KEY` |
| `eligibility_client.rb` | 270/271 — `POST /healthcare/eligibility` | Builds 270 payload, parses 271 → plan name, coverage/network status, benefits |
| `benefit_extractor.rb` | 271 `benefitsInformation` parser | Prioritized STC ladder (`A6/CF` → `MH/BH` → `A4` → `30`, tiers 1–3 report `mh_specific`); copay/coinsurance/deductible/OOP/visit-limit in cents; `resolve_pair` accumulator logic; winning tier audited in `stc_sources` |
| `claim_client.rb` | 837P claim submission | Full payload builder; `PLACE_OF_SERVICE`, `FREQUENCY_CODES = {original: "1", corrected: "7", void: "8"}`, `TEST_PAYER_ID = "STEDITEST"` |
| `claim_status_client.rb` | 276/277 claim status | Normalized status, payment info, denial info |
| `era_client.rb` | 835 ERA — `/polling/transactions` | `CLAIM_STATUS_CODES` (CLP02 map), CARC adjustments, `DEFAULT_LOOKBACK = 30.days` |
| `payers_directory_client.rb` | Payers directory CSV | Bulk payer fetch, separate base URL |
| `payers_directory_parser.rb` | Payer CSV parser | `REQUIRED_HEADERS = %w[StediId PrimaryPayerId]` |

## Pipeline services (`app/services/`)

**Claim generation/submission**: `generate_claim_service.rb`, `generate_claim_for_appointment_service.rb` (auto-claim from end-of-session popup; skip + dedup rules), `validate_claim_service.rb`, `submit_claim_service.rb`, `submit_claim_appeal_service.rb` (corrected claim, frequency 7)

**Eligibility/benefits**: `verify_eligibility_service.rb`, `auto_verify_eligibility_service.rb`, `apply_eligibility_benefits_service.rb` (provenance-aware guards), `determine_copay_service.rb`, `update_billing_fields_service.rb`

**ERA/posting/reconciliation**: `process_era_service.rb`, `match_era_to_claims_service.rb`, `compute_era_reconciliation_service.rb`, `apply_era_reconciliation_service.rb` (advisory-locked approval engine), `link_era_reconciliation_service.rb`, `dismiss_era_reconciliation_service.rb`, `derive_era_adjustment_policy_changes_service.rb` (pure CARC-PR → policy accumulator calculator)

**Payers/reporting**: `generate_denial_report_service.rb`, `generate_aging_report_service.rb`, `generate_superbill_service.rb`

## Models

- `insurance_claim.rb` — status: `draft → validated → submitted → accepted → pending → paid/denied`, plus `void`. `claim_type`: original/corrected/void. Transition methods `validate!`, `submit!`, `mark_accepted!`, `mark_pending!`, `mark_paid!`, `mark_denied!`, `void!`
- `claim_line_item.rb` — `HasPlaceOfService`; modifier format `/\A[A-Z0-9]{2}\z/`
- `claim_payment.rb` — payment_type: insurance/patient/adjustment/write_off; `#post!` enqueues `EraReconciliationJob`
- `era_reconciliation.rb` — status: auto_resolved/pending_review/unlinked/approved/dismissed; direction: none/credit_due/additional_owed; `TOLERANCE_CENTS = 100`
- `eligibility_check.rb` — status: pending/success/failed/error; `benefit_source`: mh_specific/plan_level
- `insurance_policy.rb` — `BENEFIT_SOURCES = %w[mh_specific plan_level manual era]`, `PROVENANCE_FIELDS`, `AUTO_WRITABLE_BENEFIT_FIELDS`
- `stedi_webhook_event.rb` — idempotency: unique `stedi_event_id`, `.already_processed?`, `.find_or_create_for_processing`
- `claim_generation_failure.rb` — unresolved-claim alerting; `needs_attention` scope
- `claim_appeal.rb` — appeal_level: first_level/second_level/external_review
- `remittance_advice.rb` — payment_method: check/eft/virtual_card

## Jobs + schedules (`config/recurring.yml`)

| Job | Schedule | Purpose |
|---|---|---|
| `claim_submission_job` | on-demand | Async 837P submission |
| `auto_generate_claim_job` | on-demand | Auto claim from session popup |
| `claim_status_sync_job` | daily 6:30 | 276/277 sweep of in-progress claims |
| `timely_filing_alert_job` | weekdays 7:00 | Timely-filing deadline alerts |
| `eligibility_check_job` / `auto_verify_eligibility_job` | on-demand | Single-policy 270/271 |
| `daily_eligibility_verification_job` | daily 6:00 | Batch eligibility sweep |
| `eligibility_check_archival_job` | daily 3:30 | NULLs `raw_response` >90 days (PHI hygiene) |
| `era_download_job` | every 2h | 835 download → RemittanceAdvice + payments |
| `era_rematch_job` | every 2h | Retry unmatched ERA payments |
| `auto_posting_job` | every 3h | Auto-post fully-matched ERAs |
| `era_reconciliation_job` | on-demand | Reconciliation after `ClaimPayment#post!` |

Stedi jobs `retry_on Stedi::BaseClient::ApiError, wait: :polynomially_longer, attempts: 3`.

## Webhooks & config

- `app/controllers/webhooks/stedi_controller.rb` — `POST /webhooks/stedi`; auth by shared-secret custom header (`STEDI_WEBHOOK_SECRET`, secure-compare — not HMAC); receives EventBridge envelopes and routes on `detail-type` in `ProcessStediWebhookEventJob`: `transaction.processed.v2` (INBOUND 835 → ERA ingest, INBOUND 277 → claim-status report, 999 and all OUTBOUND → record-only), `file.delivered.v2` (record-only), `file.failed.v2` (loud Honeybadger page — claim file never reached the payer). Envelope-id dedup via `StediWebhookEvent`; rate-limited 100 req/min in `config/initializers/rack_attack.rb`.
- `config/stedi.yml` — base URLs, `usage_indicator` (T dev / P prod), timeouts, `service_type_codes: {mental_health: "MH", behavioral_health: "A4"}`
- `config/initializers/insurance_features.rb` — feature flags: `eligibility_enabled?`, `claims_enabled?`, `era_enabled?`, `auto_eligibility_enabled?`
- ENV: `STEDI_API_KEY`, `STEDI_TEST_API_KEY`, `STEDI_WEBHOOK_SECRET`, `STEDI_USE_TEST_KEY`, `INSURANCE_MODULE_ENABLED`, `STEDI_*_ENABLED`

## Mental-health billing constants

- `app/models/appointment.rb` — `THERAPY_CPT_CODES = %w[90832 90834 90837 90846 90847 90853]`; `#suggested_cpt_code` (90791 initial assessment, duration-banded individual codes, 90847 family); `#suggested_modifiers` appends `"95"` for telehealth; `#place_of_service_code` returns "10"/"02" telehealth (home/other) / "11" office — see POS derivation note below
- `app/models/concerns/has_place_of_service.rb` — full CMS POS list incl. "02", "10", "11", "53"
- `app/services/stedi/benefit_extractor.rb` — `BENEFIT_CODES = {copay: "B", coinsurance: "A", deductible: "C", out_of_pocket_max: "G", visit_limit: "F"}`
- `app/services/stedi/era_client.rb` — CLP02 map: 1/2/3/19/20/21 → paid, 4 → denied, 22 → adjusted, 23/25 → unknown
- `app/models/fee_schedule.rb` — `rate_for(cpt_code, modifiers: [])`

**POS derivation (resolved 2026-08-07)**: `Appointment#telehealth?` (virtual office OR video meeting) is the single telehealth signal; `Appointment#place_of_service_code` returns "10" (home — also the default when the popup-captured `telehealth_client_location` is unanswered), "02" (other location), or "11" (office). End-of-session popups capture the client location. `Stedi::ClaimClient#place_of_service_code` resolves claim POS → line POS → appointment → org default → neutral "11", then applies the curated `Payer#telehealth_pos` override (a top-level `submission_requirements` key that survives payer resync).

## Docs in repo

- `docs/STEDI_BILLING_TECHNICAL.md` — engineer-facing end-to-end claim trace, config checklist, go-live checklist
- `docs/STEDI_BILLING_WALKTHROUGH.md` — biller-facing plain-language runbook
- `docs/STEDI_CLAIM_SUBMISSION_AUDIT.md` — audit vs Stedi 837P requirements; pre-launch checklist
- `docs/STEDI_ELIGIBILITY_ACCURACY_REVIEW.md` — 271 parsing accuracy review vs Stedi schema
- `docs/BILLING_USER_GUIDE.md` — user-facing billing guide (must stay current per CLAUDE.md)

## Tests

- `spec/services/stedi/` — one spec per client
- Service/job/model/policy/component specs for the entire pipeline (see `spec/services/`, `spec/jobs/`, `spec/models/`)
- `spec/requests/webhooks/stedi_spec.rb` — webhook endpoint
- `spec/support/stedi_helpers.rb`, `spec/fixtures/vcr_cassettes/stedi/`
- System specs: `spec/system/insurance_claims/`, `spec/system/claim_appeals/`, `spec/system/insurance_policies/eligibility_spec.rb`, `mh_benefit_provenance_spec.rb`

## Fixture policy (enforced)

Stedi response fixtures are NEVER hand-invented — see "Fixture policy" in `docs/STEDI_BILLING_TECHNICAL.md`:

- `spec/support/stedi_schema_validator.rb` — validates every WebMock-served Stedi response body against Stedi's vendored OpenAPI schemas (`spec/fixtures/stedi/schema/`, pinned in `VERSION.yml`) in strict unknown-keys-rejected mode. Out-of-contract resilience specs opt out per-example with `stedi_schema: :skip` + justifying comment. Faraday-double specs call `StediSchemaValidator.validate!` explicitly.
- `spec/fixtures/stedi/` + `manifest.yml` — fixture library with per-file provenance (documented_example / recorded_test_mode / sanitized_production); load via `StediSchemaValidator.load_fixture`.
- `spec/stedi_fixtures/stedi_fixture_contract_spec.rb` — contract spec: phantom-shape regression tests, fixture validation, manifest coverage.
- Rake: `stedi:refresh_openapi_schema` (re-pin schemas), `stedi:export_sanitized_fixture[id]` (PHI-scrub a raw_response to tmp/ for human review).
- Key shape facts the guard enforces: money/quantities are decimal STRINGS ("25", "0.2"); meta has traceId (no requestId/responseId); planInformation has no planName/planType/effectiveDate/terminationDate (use planStatus.planDetails / benefitsInformation planCoverage + insuranceTypeCode / planDateInformation); 835 BPR04 enum is ACH/BOP/CHK/FWT/NON; poll-transaction items require artifacts/partnership/mode/full x12.metadata.
