#!/usr/bin/env ruby
# frozen_string_literal: true

# Mutation probe: break ONE line of source on purpose, run the spec, put the line back.
# A good spec fails (KILLED). If it still passes (SURVIVED), nothing asserts on that behavior.
#
#   TEST_ENV_NUMBER=3 bundle exec ruby .claude/skills/rspec-test-expert/scripts/probe.rb \
#     --file app/services/foo_service.rb --line 42 --from ">= 18" --to "> 18" \
#     spec/services/foo_service_spec.rb
#
#   --from/--to  literal substring replacement on that line (first occurrence)
#   --replace    replace the whole line (keep indentation yourself), e.g. --replace "    return failure('x')"
#   --why TEXT   optional label echoed in the result line
#
# Safety: refuses to run if the source file has uncommitted changes, restores the original
# bytes in an ensure block (and on INT/TERM), and verifies `git diff` is clean afterwards.
# Output: one line — KILLED / SURVIVED / INVALID (spec could not load: the mutation broke
# syntax or loading, which proves nothing) — plus the rspec summary.

require "open3"
require "optparse"

opts = {}
OptionParser.new do |o|
  o.on("--file F") { |v| opts[:file] = v }
  o.on("--line N", Integer) { |v| opts[:line] = v }
  o.on("--from S") { |v| opts[:from] = v }
  o.on("--to S") { |v| opts[:to] = v }
  o.on("--replace S") { |v| opts[:replace] = v }
  o.on("--why S") { |v| opts[:why] = v }
end.parse!(ARGV)
specs = ARGV

file, line_no = opts[:file], opts[:line]
abort "usage: probe.rb --file F --line N (--from A --to B | --replace LINE) SPEC..." unless file && line_no && specs.any?
abort "no such file: #{file}" unless File.exist?(file)
unless opts[:replace] || (opts[:from] && opts.key?(:to))
  abort "give --from/--to or --replace"
end

dirty, = Open3.capture2("git", "status", "--porcelain", "--", file)
abort "REFUSED: #{file} has uncommitted changes; commit or stash them so the restore is provable" unless dirty.strip.empty?

original = File.binread(file)
lines = original.lines
abort "line #{line_no} out of range (file has #{lines.size})" unless line_no.between?(1, lines.size)
old_line = lines[line_no - 1]

new_line =
  if opts[:replace]
    opts[:replace].end_with?("\n") ? opts[:replace] : opts[:replace] + "\n"
  else
    abort "--from #{opts[:from].inspect} not found on line #{line_no}: #{old_line.strip}" unless old_line.include?(opts[:from])
    old_line.sub(opts[:from]) { opts[:to] }
  end
abort "mutation is a no-op" if new_line == old_line

restore = -> { File.binwrite(file, original) if File.binread(file) != original }
%w[INT TERM].each { |sig| trap(sig) { restore.call; exit 130 } }

out = status = nil
begin
  mutated = lines.dup
  mutated[line_no - 1] = new_line
  File.binwrite(file, mutated.join)
  env = ENV.to_h.reject { |k, _| k == "COVERAGE" }
  out, status = Open3.capture2e(env, "bundle", "exec", "rspec", *specs, "--format", "progress", "--no-color")
ensure
  restore.call
end

_, clean = Open3.capture2("git", "diff", "--quiet", "--", file)
abort "RESTORE FAILED: #{file} differs from HEAD — run `git checkout -- #{file}` NOW" unless clean.success?

summary = out[/^\d+ examples?, \d+ failures?.*$/] || "(no summary)"
load_error = out.match?(/error(s)? occurred outside of examples/) || out.match?(/^(SyntaxError|NameError|LoadError)\b/)
verdict =
  if load_error then "INVALID"
  elsif status.success? then "SURVIVED"
  else "KILLED"
  end

label = opts[:why] ? " [#{opts[:why]}]" : ""
puts "#{verdict}#{label} #{file}:#{line_no}  #{old_line.strip}  =>  #{new_line.strip}"
puts "  #{summary}"
if verdict == "KILLED"
  failed = out.scan(/^rspec (\S+) # (.+)$/).first(3)
  failed.each { |loc, desc| puts "  caught by #{loc} — #{desc}" }
end
