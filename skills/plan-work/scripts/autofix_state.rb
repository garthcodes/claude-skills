# Read-only autofix queue snapshot for /plan-work. Run: bin/prod-read < this file
# Prints one JSON line (last line of output). Labels and ids only, no PHI.
require "json"

status = Autofix::Status.instance
puts JSON.generate(
  paused: status.paused,
  backoff_until: status.backoff_until,
  slots: Autofix::Dispatcher::MAX_RUNNING,
  running: Autofix::Run.running.includes(:item).map { |r| {routine: r.routine, target: r.item&.label || "group #{r.issue_numbers.join(",")}", fired_at: r.fired_at, phase: r.phase} },
  queued: Autofix::Item.queued.oldest_first.map { |i| {target: i.label, queued_at: i.queued_at} },
  finished_24h: Autofix::Run.where(finished_at: 24.hours.ago..).recent_first.includes(:item).map { |r| {target: r.item&.label, status: r.status, pr: r.pr_number, result: r.result_line} },
  skipped_24h: Autofix::Item.skipped.where(updated_at: 24.hours.ago..).where.not(reason: Autofix::Dispatcher::SEEN_REASON).map { |i| {target: i.label, reason: i.reason} }
)
