# Read-only revenue-cycle health snapshot. Counts, dollars and ages only — no
# names, no clinical text, no ids (ask for ids in a follow-up probe when needed).
#
#   bin/prod-read < .claude/skills/rcm-audit/scripts/rcm_snapshot.rb    # production
#   bin/rails runner .claude/skills/rcm-audit/scripts/rcm_snapshot.rb   # local dev
#
# Each line is tagged with the audit area it points at (see references/audit-areas.md).
# A metric that raises prints "ERROR <class>" instead of aborting the run, so a schema
# drift in one probe never hides the others.

today = StaffTimeHelper.staff_today
dollars = ->(cents) { format("$%.2f", cents.to_i / 100.0) }
age = ->(date) { date ? "#{(today - date.to_date).to_i}d" : "-" }

def metric(area, label)
  value = yield
  puts format("  %-4s %-66s %s", area, label, value)
rescue => e
  puts format("  %-4s %-66s ERROR %s", area, label, e.class)
end

Organization.find_each do |org|
  ActsAsTenant.with_tenant(org) do
    puts "== org #{org.id} (as of #{today.strftime("%m/%d/%Y")})"

    metric("A1", "past sessions with no outcome recorded (count, oldest)") do
      scope = Appointment.unresolved
      "#{scope.count}, #{age.call(scope.minimum(:start_time))}"
    end

    metric("A1", "completed billable sessions, last 120d, no invoice AND no claim") do
      Appointment.billable.status_completed
        .where(start_time: 120.days.ago..)
        .where.not(id: Invoice.where.not(appointment_id: nil).select(:appointment_id))
        .where.not(id: InsuranceClaim.where.not(appointment_id: nil).select(:appointment_id))
        .count
    end

    metric("A3", "unresolved claim-generation failures (count, oldest)") do
      scope = ClaimGenerationFailure.unresolved
      "#{scope.count}, #{age.call(scope.minimum(:created_at))}"
    end

    metric("A3", "claims in draft/validated > 7d (count, $, oldest DOS)") do
      scope = InsuranceClaim.where(status: [:draft, :validated]).where(created_at: ..7.days.ago)
      "#{scope.count}, #{dollars.call(scope.sum(:total_charge_cents))}, #{age.call(scope.minimum(:service_date_from))}"
    end

    metric("A4", "claims submitted > 7d with no acceptance (count, $)") do
      scope = InsuranceClaim.status_submitted.where(submitted_at: ..7.days.ago)
      "#{scope.count}, #{dollars.call(scope.sum(:total_charge_cents))}"
    end

    metric("A5", "claims accepted/pending > 45d since submit (count, $)") do
      scope = InsuranceClaim.where(status: [:accepted, :pending]).where(submitted_at: ..45.days.ago)
      "#{scope.count}, #{dollars.call(scope.sum(:total_charge_cents))}"
    end

    metric("A5", "open claims with DOS > 90d ago (timely-filing zone) (count, $)") do
      scope = InsuranceClaim.where(status: [:draft, :validated, :submitted, :accepted, :pending])
        .where(service_date_from: ..(today - 90))
      "#{scope.count}, #{dollars.call(scope.sum(:total_charge_cents))}"
    end

    metric("A7", "denied claims, last 180d (count, $)") do
      scope = InsuranceClaim.status_denied.where(updated_at: 180.days.ago..)
      "#{scope.count}, #{dollars.call(scope.sum(:total_charge_cents))}"
    end

    metric("A6", "ERAs failed or unprocessed > 1d (count)") do
      RemittanceAdvice.where(status: [:received, :processing, :failed]).where(created_at: ..1.day.ago).count
    end

    metric("A6", "claim payments pending (unposted) > 7d (count, $)") do
      scope = ClaimPayment.status_pending.where(created_at: ..7.days.ago)
      "#{scope.count}, #{dollars.call(scope.sum(:amount_cents))}"
    end

    metric("A6", "ERA reconciliations pending_review/unlinked (count, $ diff)") do
      scope = EraReconciliation.where(status: [:pending_review, :unlinked])
      "#{scope.count}, #{dollars.call(scope.sum("ABS(difference_cents)"))}"
    end

    metric("A8", "invoices draft with due date passed (count, $)") do
      scope = Invoice.status_draft.where(due_date: ...today)
      "#{scope.count}, #{dollars.call(scope.sum(:amount_cents))}"
    end

    metric("A9", "invoices failed/requires_action (count, $)") do
      scope = Invoice.where(status: [:failed, :requires_action])
      "#{scope.count}, #{dollars.call(scope.sum(:amount_cents))}"
    end

    metric("A9", "invoices sent and > 30d past due (count, $)") do
      scope = Invoice.status_sent.where(due_date: ..(today - 30))
      "#{scope.count}, #{dollars.call(scope.sum(:amount_cents))}"
    end
  end
end
