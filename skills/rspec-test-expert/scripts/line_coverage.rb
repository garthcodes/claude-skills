#!/usr/bin/env ruby
# frozen_string_literal: true

# Which lines of ONE source file does a spec actually execute?
#
#   TEST_ENV_NUMBER=3 bundle exec ruby .claude/skills/rspec-test-expert/scripts/line_coverage.rb \
#     app/services/foo_service.rb spec/services/foo_service_spec.rb [--save tmp/before.json] [--baseline tmp/before.json]
#
# Multiple sources: separate with commas (e.g. a component's .rb and .html.erb).
# Prints one JSON object on stdout. rspec's own output goes to stderr.
#   --save FILE      also write the JSON to FILE (take a baseline before rewriting a spec)
#   --baseline FILE  compare against a saved run; reports `lost_lines` (covered before, not now)
#
# Uses Ruby's Coverage directly instead of SimpleCov, so concurrent runs on different
# TEST_ENV_NUMBER databases never fight over coverage/.resultset.json.
# Line coverage says a line RAN, not that anything asserted on it — pair with probe.rb.

require "json"
require "coverage"

args = ARGV.dup
save_path = (i = args.index("--save")) ? args.slice!(i, 2).last : nil
baseline_path = (i = args.index("--baseline")) ? args.slice!(i, 2).last : nil
abort "usage: line_coverage.rb SOURCE[,SOURCE] SPEC [SPEC...] [--save F] [--baseline F]" if args.size < 2

sources = args.shift.split(",").map { |s| File.expand_path(s) }
specs = args
sources.each { |s| abort "no such source file: #{s}" unless File.exist?(s) }

ENV.delete("COVERAGE") # keep SimpleCov out of the way
Coverage.start(lines: true, eval: true)

require "rspec/core"
rspec_exit = RSpec::Core::Runner.run(specs, $stderr, $stderr)
raw = Coverage.result

root = Dir.pwd + "/"
load_error = RSpec.world.respond_to?(:non_example_failure) && RSpec.world.non_example_failure
report = {"rspec_exit" => rspec_exit, "load_error" => !!load_error, "files" => {}}
warn "line_coverage: the spec did not load (error outside examples) — these numbers are meaningless" if load_error
sources.each do |src|
  lines = raw.dig(src, :lines)
  rel = src.delete_prefix(root)
  if lines.nil?
    report["files"][rel] = {"loaded" => false, "note" => "file never loaded by this spec run"}
    next
  end
  relevant = lines.each_index.reject { |i| lines[i].nil? }
  uncovered = relevant.select { |i| lines[i].zero? }.map { |i| i + 1 }
  covered = relevant.size - uncovered.size
  report["files"][rel] = {
    "loaded" => true,
    "relevant" => relevant.size,
    "covered" => covered,
    "pct" => relevant.empty? ? 100.0 : (100.0 * covered / relevant.size).round(1),
    "uncovered_lines" => uncovered
  }
end

if baseline_path
  base = JSON.parse(File.read(baseline_path))
  report["files"].each do |rel, now|
    before = base.dig("files", rel)
    next unless before&.fetch("loaded", false) && now["loaded"]
    now["lost_lines"] = now["uncovered_lines"] - before["uncovered_lines"]
    now["gained_lines"] = before["uncovered_lines"] - now["uncovered_lines"]
  end
end

json = JSON.pretty_generate(report)
File.write(save_path, json) if save_path
puts json
exit(rspec_exit.zero? ? 0 : 1)
