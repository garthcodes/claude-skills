# Revenue-cycle audit areas

The money moves through these stages in order. Each area names the question that matters, where the code lives, the ways it typically leaks money, and what to look for in production. Paths were verified 2026-10-10 — confirm they still exist before citing them; new services appear often.

The snapshot (`scripts/rcm_snapshot.rb`) tags each metric with one of these area codes.

| Code | Area | Uses /stedi-billing-expert |
|---|---|---|
| A1 | Session → billable event | |
| A2 | Eligibility & patient cost share | yes |
| A3 | Claim generation & validation | yes |
| A4 | Claim submission & acknowledgment | yes |
| A5 | Claim follow-up & timely filing | yes |
| A6 | ERA ingest, matching & posting | yes |
| A7 | Denials, corrected claims & appeals | yes |
| A8 | Patient invoicing & pricing | |
| A9 | Patient collection (Stripe) | |
| A10 | Ledger, reconciliation & visibility | |

---

## A1 — Session → billable event

**Question:** Does every session that happened turn into something we bill — and nothing we shouldn't?

**Code:** `app/services/record_appointment_outcome_service.rb`, `cancel_appointment_service.rb` (late-cancel / no-show fees), `defer_session_outcome_popup_service.rb`, `app/jobs/session_outcome_escalation_job.rb`, `Appointment.unresolved` / `.billable` scopes and `#suggested_cpt_code` / `#suggested_modifiers` / `#place_of_service_code` in `app/models/appointment.rb`, `app/jobs/generate_missing_invoices_job.rb`, `app/jobs/auto_generate_claim_job.rb`.

**Typical leaks:** a session left `booked` forever (no outcome → no claim, no invoice); outcome popup deferral that never re-asks; a status/type/category combination that falls outside `billable` by accident (NULL columns and `NOT IN`); late-cancel/no-show fee not created for one cancellation path; CPT derived from scheduled length instead of actual; telehealth flag missed → wrong modifier/POS; group sessions billing only one member; supervisee sessions missing the supervising provider.

**Prod probes:** age distribution of `Appointment.unresolved`; completed billable sessions with neither invoice nor claim, grouped by `appointment_type` / `therapy_type` / `source` (an imported `source` with a hole is a common pattern); cancellations with `cancellation_reason_late_cancellation` and no `late_fee` invoice.

## A2 — Eligibility & patient cost share

**Question:** Do we know what the payer covers and what the client owes *before* the session, and is it right?

**Code:** `verify_eligibility_service.rb`, `auto_verify_eligibility_service.rb`, `transient_eligibility_retry_service.rb`, `apply_eligibility_benefits_service.rb`, `apply_eligibility_rejection_service.rb`, `determine_copay_service.rb`, `update_billing_fields_service.rb`, `resurface_ending_coverage_service.rb`, `app/services/stedi/eligibility_client.rb`, `benefit_extractor.rb`, `medicare_benefits.rb`, `app/jobs/daily_eligibility_verification_job.rb`. Doc: `docs/STEDI_ELIGIBILITY_ACCURACY_REVIEW.md`.

**Typical leaks:** reading 271 fields Stedi doesn't return → copay silently 0; plan-level benefits used when MH carve-out exists; deductible remaining vs total confused; failed/errored checks that nobody sees; policies never re-verified after a terminate date; a stale 271 overwriting ERA-derived truth.

**Prod probes:** policies on upcoming sessions whose last successful check is > 30 days old or failed; count of checks by `status` over 30 days; sessions billed with a copay of 0 on a policy that has a non-zero copay elsewhere.

## A3 — Claim generation & validation

**Question:** Does every insured session become a valid claim promptly — and does every skip reach a human?

**Code:** `generate_claim_for_appointment_service.rb`, `generate_claim_service.rb`, `validate_claim_service.rb`, `provider_billing_readiness.rb`, `app/models/claim_generation_failure.rb` (`needs_attention`), `app/jobs/auto_generate_claim_job.rb`.

**Typical leaks:** a silent `return` / `failure` path that doesn't create a `ClaimGenerationFailure`; `needs_attention` `limit(100)` or `recent` hiding older failures; dedup that treats a voided/denied claim as "already has a claim"; claims stuck in `draft`/`validated` because validation errors aren't shown anywhere; secondary insurance never claimed.

**Prod probes:** unresolved failures by age; insured completed sessions (client has an active policy on the DOS) with no claim; drafts older than 7 days and their `validation_errors` keys (keys only, not values).

## A4 — Claim submission & acknowledgment

**Question:** Does every claim we submit actually reach the payer, and do we notice when it doesn't?

**Code:** `submit_claim_service.rb`, `app/jobs/claim_submission_job.rb`, `app/services/stedi/claim_client.rb` (837P payload), `app/controllers/webhooks/stedi_controller.rb` + `ProcessStediWebhookEventJob`, `process_claim_status_report_service.rb`, `app/jobs/claim_acknowledgement_sweep_job.rb`, `config/initializers/insurance_features.rb`. Docs: `docs/STEDI_CLAIM_SUBMISSION_AUDIT.md`, `docs/FIRST_REAL_CLAIM_PLAYBOOK.md`.

**Typical leaks:** 999/277CA rejections recorded but not surfaced; `file.failed` that pages Honeybadger but leaves the claim `submitted`; job retries that double-submit (payer duplicate denial); payload fields wrong for one payer family (taxonomy, NPI type, rendering vs billing provider, EAP modifiers, POS); `submission_enqueued_at` set but job never ran.

**Prod probes:** claims `submitted` > 7 days with no 277CA; claims with `submission_enqueued_at` but no `submitted_at`; `StediWebhookEvent` failures by type.

## A5 — Claim follow-up & timely filing

**Question:** Does every in-flight claim reach paid/denied under someone's watch before its deadline?

**Code:** `app/jobs/claim_status_sync_job.rb` (ERA-first, throttled), `app/services/stedi/claim_status_client.rb`, `claim_status_category.rb`, `app/jobs/timely_filing_alert_job.rb`, `Payer#appeal_deadline_days` / filing-limit fields, `generate_aging_report_service.rb`.

**Typical leaks:** a status (e.g. `accepted`) excluded from the sync or alert scope; throttle windows that leave a claim unpolled past its filing limit; timely-filing math from `updated_at` instead of DOS; alerts emailed to a role nobody holds; claims that go dark because 835s land in another system (see the `/legacy-claim-status` skill — ERAs for some claims still route to the legacy system).

**Prod probes:** open claims by days since DOS vs the payer's filing limit; accepted/pending claims with no status check in N days.

## A6 — ERA ingest, matching & posting

**Question:** Is every dollar the payer sends posted to the right claim, exactly once, with the right patient responsibility?

**Code:** `app/jobs/era_download_job.rb`, `ingest_era_service.rb`, `era_processor.rb`, `era_claim_matcher.rb`, `app/jobs/era_rematch_job.rb`, `era_auto_poster.rb`, `compute_era_reconciliation_service.rb`, `apply_era_reconciliation_service.rb`, `apply_era_reconciliation_batch_service.rb`, `era_reconciliation_routing_service.rb`, `era_reconciliation_outcome_hooks.rb`, `link_era_reconciliation_service.rb`, `app/services/concerns/era_line_rules.rb`, `charge_virtual_card_service.rb`, `zero_paid_era_payment_backfiller.rb`, `app/services/stedi/era_client.rb`.

**Typical leaks:** CLP02 22 reversal posted as new money; CO adjustments flowing to the patient's bill (illegal under network contracts); a duplicate 835 double-posting; unmatched payments that never escalate; float math on cents; reconciliation tolerance masking a real shortfall; virtual-card payments never charged.

**Prod probes:** `RemittanceAdvice` in received/processing/failed > 1 day; `ClaimPayment` pending > 7 days; reconciliations in `pending_review`/`unlinked` by age; virtual-card ERAs with no `virtual_card_charged_at`.

## A7 — Denials, corrected claims & appeals

**Question:** When a payer says no, does someone find out, and can they fix and resubmit in time?

**Code:** `generate_denial_report_service.rb`, `submit_claim_appeal_service.rb` (frequency 7), `app/models/claim_appeal.rb`, `InsuranceClaim#denial_codes`, claim UI under `app/views/insurance_claims/` and `app/components/`.

**Typical leaks:** denial codes stored but not shown on any work queue; corrected claim missing the payer ICN → duplicate rejection; denied claim never rebilled to the client when the denial makes it patient responsibility; appeal deadline not tracked.

**Prod probes:** denied claims by `denial_codes` (codes only) and age, and how many have an appeal, a corrected claim, or a patient invoice.

## A8 — Patient invoicing & pricing

**Question:** Is every client invoiced the right amount at the right time?

**Code:** `invoice_generation_service.rb`, `auto_generate_invoices_service.rb`, `app/jobs/generate_missing_invoices_job.rb`, `coverage_end_invoice_repricer.rb`, `adjust_invoice_for_cpt_change_service.rb`, `apply_invoice_adjustment_service.rb`, `recalculate_unpaid_invoices_service.rb`, `apply_credit_to_invoice_service.rb`, `restored_duplicate_invoice_resolver.rb`, `app/models/fee_schedule.rb`, contract fee-schedule services. Docs: `docs/INVOICE_LIFECYCLE.md`, `docs/BILLING_USER_GUIDE.md`, `.claude/audits/billing-invoice-repricing-audit.md`.

**Typical leaks:** drafts that never move to `sent`; repricing that misses invoices with a particular `cost_share_source`; duplicates after restore; credits not applied; CPT change not re-pricing; self-pay vs insurance pricing chosen wrong on migrated rows (missing metadata markers).

**Prod probes:** draft invoices whose session has passed, grouped by `invoice_type` and `cost_share_source`; invoices whose amount disagrees with the current fee schedule for that CPT.

## A9 — Patient collection (Stripe)

**Question:** When a client owes money, do we actually collect it — and when a charge fails, does someone follow up?

**Code:** `app/jobs/daily_invoice_charging_job.rb`, `charge_invoice_job.rb`, `manual_invoice_charge_job.rb`, `bulk_charge_invoices_service.rb`, `stripe_invoice_charge_attempt_service.rb`, `stripe_invoice_service.rb`, `stripe_payment_service.rb`, `reopen_invoice_for_charge_service.rb`, `process_public_payment_service.rb`, `payment_method_service.rb`, `app/controllers/webhooks/stripe_controller.rb`, `app/services/concerns/stripe_decline_messages.rb`, `stripe_refund_service.rb`.

**Typical leaks:** a failed charge never retried; `requires_action` (3DS) with no client notification; a webhook that marks paid without the money; charging before the insurance result is known then never truing up; clients with no card on file never asked for one; idempotency keys missing on retries (double charge → refund churn).

**Prod probes:** failed/requires_action invoices by age; sent invoices past due by age; clients with unpaid invoices and no active payment method.

## A10 — Ledger, reconciliation & visibility

**Question:** Can the practice see what it is owed, and does every number agree?

**Code:** `client_ledger_service.rb`, `reconciliation_client_queue_service.rb`, `invoice_workbench_queue_service.rb`, `generate_aging_report_service.rb`, `app/services/superbill/`, dashboards and work queues.

**Typical leaks:** balances computed two different ways that disagree; work queues that filter out the oldest items; aging report excluding a status; superbills missing sessions so out-of-network clients can't get reimbursed (and stop paying).

**Prod probes:** per-client ledger balance vs sum of open invoices (counts of mismatches, not names).
