#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the spec-sweep work queue: every unit spec, its source file, its size, and a
# "fat score" from cheap static smells. Worst files first, grouped into batches by category,
# capped by spec count (--batch-size) and total spec lines (--max-lines, default 2500).
#
#   ruby .claude/skills/spec-sweep/scripts/inventory.rb [--only GLOB] [--categories models,services]
#        [--batch-size 8] [--ledger .claude/audits/spec-sweep/ledger.jsonl] [--out FILE] [--top 15]
#
# Plain Ruby, no Rails boot — runs in about a second. Files already recorded as `done` or
# `skipped` in the ledger are left out, which is what makes the sweep resumable.
# Static smells are only a triage signal: a file that scores 0 can still be weak, and a
# smell hit can be legitimate. The worker reading the spec decides.

require "json"
require "time"
require "optparse"

CATEGORIES = {
  "models" => {skill: "model-test", src: ->(p) { ["app/#{p}.rb"] }},
  "services" => {skill: "service-test", src: ->(p) { ["app/#{p}.rb"] }},
  "policies" => {skill: "policy-test", src: ->(p) { ["app/#{p}.rb"] }},
  "components" => {skill: "viewcomponent-test-expert", src: ->(p) { ["app/#{p}.rb", "app/#{p}.html.erb"] }},
  "jobs" => {skill: "rspec-test-expert", src: ->(p) { ["app/#{p}.rb"] }},
  "mailers" => {skill: "rspec-test-expert", src: ->(p) { ["app/#{p}.rb"] }},
  "helpers" => {skill: "rspec-test-expert", src: ->(p) { ["app/#{p}.rb"] }},
  "channels" => {skill: "rspec-test-expert", src: ->(p) { ["app/#{p}.rb"] }},
  "lib" => {skill: "rspec-test-expert", src: ->(p) { [p.sub(%r{\Alib/}, "lib/") + ".rb"] }},
  "tasks" => {skill: "rspec-test-expert", src: ->(p) { [p.sub(%r{\Atasks/}, "lib/tasks/") + ".rake"] }},
  "initializers" => {skill: "rspec-test-expert", src: ->(p) { [p.sub(%r{\Ainitializers/}, "config/initializers/") + ".rb"] }}
}.freeze

# name => [regex, weight]. Weights reflect how reliably the pattern means "asserts nothing useful".
SMELLS = {
  "superclass_assert" => [/\.superclass\)\.to eq|\.ancestors\)\.to include|included_modules\)\.to include/, 3],
  "ivar_peek" => [/instance_variable_get/, 3],
  "private_send" => [/\.send\(:[a-z_]+[?!]?/, 1],
  "type_only_assert" => [/to be_a(n)?\((Result|described_class|Hash|Array|String|Integer|ActiveSupport::SafeBuffer)\)|to be\(true\)\.or be\(false\)/, 2],
  "renders_anything" => [/\(rendered\)\.to be_present|\(page\)\.to be_present|to_html\)\.to be_present/, 3],
  "not_raise_only" => [/not_to raise_error/, 1],
  "respond_to" => [/to respond_to\(/, 2],
  "logger_assert" => [/Rails\.logger\)\.to (have_)?receive/, 1],
  "stubs_subject" => [/allow\((subject|service|component|described_class)\)\.to receive|allow_any_instance_of\(described_class\)/, 3],
  "css_class_assert" => [/\[["']class["']\]\)\.to include|to include\(["'](bg|text|border|px|py|p|m|mx|my|h|w|rounded|flex|grid|gap|font|shadow)-/, 1],
  "html_substring" => [/to_html\)\.to include/, 1],
  "factory_selftest" => [/(creates|builds|has) a valid (factory|record)|factory.*be_valid|be_valid.*factory/i, 2],
  "frozen_or_constant_size" => [/to be_frozen|::[A-Z_]+(\.keys)?\.size\)\.to eq/, 2],
  "loose_presence" => [/\.to be_present\s*$|\.to be_truthy|\.to be_falsey|not_to be_nil\s*$/, 1],
  "any_instance" => [/any_instance_of/, 1],
  "message_chain" => [/receive_message_chain/, 2],
  "disabled_example" => [/^\s*(xit|xdescribe|xcontext|pending|skip)\b/, 2]
}.freeze

opts = {batch_size: 8, max_lines: 2500, ledger: ".claude/audits/spec-sweep/ledger.jsonl", top: 15, categories: CATEGORIES.keys}
OptionParser.new do |o|
  o.on("--only GLOB") { |v| opts[:only] = v }
  o.on("--categories LIST") { |v| opts[:categories] = v.split(",") }
  o.on("--batch-size N", Integer) { |v| opts[:batch_size] = v }
  o.on("--max-lines N", Integer) { |v| opts[:max_lines] = v }
  o.on("--ledger FILE") { |v| opts[:ledger] = v }
  o.on("--out FILE") { |v| opts[:out] = v }
  o.on("--top N", Integer) { |v| opts[:top] = v }
end.parse!(ARGV)

unknown = opts[:categories] - CATEGORIES.keys
abort "unknown categories: #{unknown.join(", ")} (known: #{CATEGORIES.keys.join(", ")})" if unknown.any?

closed = {}
if File.exist?(opts[:ledger])
  File.foreach(opts[:ledger]) do |l|
    next if l.strip.empty?
    e = JSON.parse(l)
    next if e["mode"] == "audit" # audits never close a spec
    closed[e["spec"]] = e["status"] if %w[done skipped].include?(e["status"])
  end
end

def count_examples(text) = text.scan(/^\s*(it|specify|example|scenario|its)\b/).size

entries = []
opts[:categories].each do |cat|
  Dir.glob("spec/#{cat}/**/*_spec.rb").sort.each do |spec|
    next if opts[:only] && !File.fnmatch?(opts[:only], spec, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    next if closed.key?(spec)
    text = File.read(spec)
    rel = spec.delete_prefix("spec/").delete_suffix("_spec.rb")
    sources = CATEGORIES[cat][:src].call(rel).select { |s| File.exist?(s) }
    src_lines = sources.sum { |s| File.foreach(s).count }
    smells = SMELLS.to_h { |name, (re, _)| [name, text.scan(re).size] }.reject { |_, n| n.zero? }
    spec_lines = text.lines.size
    ratio = src_lines.positive? ? (spec_lines.to_f / src_lines).round(1) : nil
    score = smells.sum { |name, n| SMELLS[name][1] * n }
    score += [((ratio - 4) * 2).round, 20].min if ratio && ratio > 4 # padded specs; capped — tiny sources (concern-only models) inflate the ratio
    entries << {
      "spec" => spec, "category" => cat, "skill" => CATEGORIES[cat][:skill], "sources" => sources,
      "orphan" => sources.empty?, "spec_lines" => spec_lines, "source_lines" => src_lines,
      "ratio" => ratio, "examples" => count_examples(text), "smells" => smells, "score" => score
    }
  end
end

batches = []
entries.group_by { |e| e["category"] }.each do |cat, list|
  # Pack worst-first, closing a batch at batch_size specs or max_lines total spec lines, so one
  # worker never has to hold 10k lines of spec in context. An oversized spec gets a batch alone.
  slices = list.sort_by { |e| -e["score"] }.each_with_object([[]]) do |e, acc|
    cur = acc.last
    over = cur.any? && (cur.size >= opts[:batch_size] || cur.sum { |x| x["spec_lines"] } + e["spec_lines"] > opts[:max_lines])
    acc << (cur = []) if over
    cur << e
  end
  slices.reject(&:empty?).each.with_index(1) do |slice, i|
    batches << {"id" => "#{cat}-#{format("%03d", i)}", "category" => cat, "skill" => CATEGORIES[cat][:skill],
                "score" => slice.sum { |e| e["score"] }, "specs" => slice}
  end
end
batches.sort_by! { |b| -b["score"] }

result = {"generated_at" => Time.now.utc.iso8601, "ledger_closed" => closed.size,
          "totals" => {"specs" => entries.size, "spec_lines" => entries.sum { |e| e["spec_lines"] },
                       "examples" => entries.sum { |e| e["examples"] }, "orphans" => entries.count { |e| e["orphan"] }},
          "batches" => batches}
File.write(opts[:out], JSON.pretty_generate(result)) if opts[:out]

t = result["totals"]
puts "Open specs: #{t["specs"]}  (#{t["spec_lines"]} lines, #{t["examples"]} examples, #{t["orphans"]} with no source file)  — #{closed.size} already closed in ledger"
puts
puts format("%-14s %6s %9s %9s", "category", "specs", "lines", "score")
entries.group_by { |e| e["category"] }.sort_by { |_, l| -l.sum { |e| e["score"] } }.each do |cat, l|
  puts format("%-14s %6d %9d %9d", cat, l.size, l.sum { |e| e["spec_lines"] }, l.sum { |e| e["score"] })
end
puts
puts "Fattest #{opts[:top]}:"
entries.sort_by { |e| -e["score"] }.first(opts[:top]).each do |e|
  top = e["smells"].sort_by { |_, n| -n }.first(3).map { |k, n| "#{k}×#{n}" }.join(" ")
  puts format("  %4d  %-62s %5d lines  %4sx src  %s", e["score"], e["spec"], e["spec_lines"], e["ratio"] || "-", top)
end
puts
puts "#{batches.size} batches of ≤#{opts[:batch_size]} specs / ≤#{opts[:max_lines]} lines#{opts[:out] ? " written to #{opts[:out]}" : " (pass --out FILE to save the queue)"}"
