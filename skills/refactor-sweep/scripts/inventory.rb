#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the refactor-sweep queue: every place the code breaks the sustainability rules
# (app/services/CLAUDE.md, app/models/CLAUDE.md, ...), as one-PR-sized targets, ranked so the
# code that changes most and is reached from most places comes first.
#
#   bundle exec ruby .claude/skills/refactor-sweep/scripts/inventory.rb \
#     [--kinds callback,model_logic,callable,locals,route,unique_index,fat_job] \
#     [--only SUBSTRING] [--ledger .claude/audits/refactor-sweep/ledger.jsonl] \
#     [--top 15] [--out FILE] [--show ID]
#
# Static heuristics, no Rails boot (about 2 s). A target is a lead, not a verdict: the
# coordinator reads the code and may widen it (sibling callbacks/services) or drop it.
# Targets whose latest ledger status is pr_open, merged, skipped or wontfix are left out,
# which is what makes the sweep resumable; `failed` targets stay in the queue.

require "json"
require "optparse"
require "active_support/core_ext/string/inflections"

opts = {kinds: nil, only: nil, ledger: ".claude/audits/refactor-sweep/ledger.jsonl", top: 15, out: nil, show: nil}
OptionParser.new do |o|
  o.on("--kinds LIST") { |v| opts[:kinds] = v.split(",") }
  o.on("--only S") { |v| opts[:only] = v }
  o.on("--ledger F") { |v| opts[:ledger] = v }
  o.on("--top N", Integer) { |v| opts[:top] = v }
  o.on("--out F") { |v| opts[:out] = v }
  o.on("--show ID") { |v| opts[:show] = v }
end.parse!(ARGV)

# How much moving each kind out of the wrong place is worth, relative to the others. Callbacks
# first: hidden side effects in models referenced from hundreds of files are the guide's main worry.
KIND_WEIGHT = {"callback" => 3.0, "model_logic" => 2.0, "callable" => 1.5, "fat_job" => 1.2,
               "unique_index" => 1.2, "route" => 1.0, "locals" => 0.8}.freeze

SIDE_EFFECT = {
  "enqueues job" => /\.perform_later\b|\.set\([^)]*\)\.perform_later|perform_async/,
  "sends mail" => /\.deliver_(later|now)\b/,
  "broadcasts" => /\bbroadcast_\w+|Turbo::StreamsChannel\./,
  "calls external API" => /\b(Stripe|Stedi\w*|Faraday|Net::HTTP|HTTParty|Google::\w+|RingRx\w*)\b|TextMessageService/,
  "calls a service" => /\b[A-Z]\w*(Service|Creator|Scheduler|Submitter|Charger)\b(\.new|\.call)/,
  "writes other records" => /\b(?!self\b)[a-z_]+\.(create!?|update!?|update_all|destroy!?|find_or_create_by!?|insert_all)\b|\b[A-Z]\w+\.(create!?|insert_all|upsert_all|update_all|find_or_create_by!?)\b/
}.freeze

src = Dir["{app,lib,config}/**/*.{rb,erb,rake,yml}"].to_h { |f| [f, File.read(f)] }

def churn_for(paths)
  return {} if paths.empty?
  counts = Hash.new(0)
  out = `git log --since=180.days --name-only --format= -- #{paths.map { |p| "'#{p}'" }.join(" ")} 2>/dev/null`
  out.each_line { |l| counts[l.strip] += 1 unless l.strip.empty? }
  counts
end

def fan_in(src, const, own)
  re = /\b#{Regexp.escape(const)}\b/
  src.count { |f, s| f != own && s.match?(re) }
end

# Body of `def name` in source (indent-matched `end`), or nil.
def method_body(text, name)
  lines = text.lines
  start = lines.index { |l| l =~ /^(\s*)def (self\.)?#{Regexp.escape(name)}\b/ }
  return nil unless start
  indent = lines[start][/^\s*/].size
  stop = (start + 1...lines.size).find { |i| lines[i] =~ /^\s{#{indent}}end\b/ } || lines.size - 1
  {start: start + 1, text: lines[start..stop].join, size: stop - start + 1}
end

def effects_in(text, file_text, depth = 1)
  found = SIDE_EFFECT.select { |_, re| text.match?(re) }.keys
  if depth.positive?
    text.scan(/\b([a-z_]\w*[!?]?)\b/).flatten.uniq.each do |call|
      next unless file_text.match?(/^\s*def #{Regexp.escape(call)}\b/)
      body = method_body(file_text, call)
      found |= effects_in(body[:text], file_text, depth - 1) if body
    end
  end
  found
end

targets = []
add = ->(t) { targets << t }

model_files = Dir["app/models/**/*.rb"].reject { |f| f.include?("/concerns/") }
churn = churn_for(model_files + Dir["app/services/**/*.rb"] + Dir["app/jobs/**/*.rb"] + Dir["app/views/**/_*.erb"] + ["config/routes.rb"])

# --- callback: model callbacks with side effects ------------------------------------------
model_files.each do |f|
  text = src[f] or next
  klass = text[/^\s*class (\w+(::\w+)*)/, 1] or next
  text.each_line.with_index(1) do |line, ln|
    next unless line =~ /^\s+((before|after|around)_\w+)\s+(:(\w+[!?]?)|->|lambda|proc)/
    hook, name = $1, $4
    body = name ? method_body(text, name) : nil
    inline = name ? nil : text.lines[ln - 1, 15].join[/\A.*?(^\s*\}|\bend\b)/m]
    effects = effects_in(body ? body[:text] : inline.to_s, text)
    next if effects.empty? || effects == ["calls a service"] && hook.start_with?("before_")
    add.call(kind: "callback", id: "callback:#{klass}##{name || "line#{ln}"}", file: f, line: ln,
      what: "#{hook} #{name ? ":#{name}" : "(lambda)"}: #{effects.join(", ")}", const: klass, churn_file: f)
  end
end

# Related callbacks (Appointment's six calendar-sync hooks) are one change, so one target: group a
# class's callbacks by a shared noun in their method names.
VERBS = %w[enqueue sync broadcast trigger send notify assign reset note capture create update destroy
  refresh resolve set clear apply handle check schedule push deletion cleanup on after before line].freeze
callbacks = targets.select { |t| t[:kind] == "callback" }
callbacks.group_by { |t| t[:const] }.each do |klass, cbs|
  next if cbs.size < 2
  words = cbs.to_h { |t| [t, t[:id].split("#").last.split("_") - VERBS] }
  counts = words.values.flatten.tally
  cbs.group_by { |t| words[t].max_by { |w| [counts[w], w.size] } }.each do |noun, group|
    next if noun.nil? || group.size < 2 || counts[noun] < 2
    group.each { |t| targets.delete(t) }
    add.call(kind: "callback", id: "callback:#{klass}[#{noun}]", file: group.first[:file], line: group.map { _1[:line] }.min,
      what: "#{group.size} callbacks: #{group.map { _1[:id].split("#").last }.join(", ")}", const: klass, churn_file: group.first[:file])
  end
end

# --- model_logic: workflow methods in big models --------------------------------------------
model_files.each do |f|
  text = src[f] or next
  next if text.lines.size < 300
  klass = text[/^\s*class (\w+(::\w+)*)/, 1] or next
  public_part = text.split(/^\s+private\b/).first
  public_part.scan(/^\s+def ((?!self\.)\w+[!?]?)/).flatten.uniq.each do |name|
    body = method_body(text, name) or next
    next if body[:size] < 8
    effects = effects_in(body[:text], text)
    next if effects.empty?
    add.call(kind: "model_logic", id: "model_logic:#{klass}##{name}", file: f, line: body[:start],
      what: "#{body[:size]}-line public method: #{effects.join(", ")}", const: klass, churn_file: f)
  end
end

# --- callable: services in the legacy constructor + call shape ------------------------------
services = Dir["app/services/**/*.rb"].reject { |f| f.include?("/concerns/") || f.end_with?("/result.rb") }
prefix = ->(f) { File.basename(f, ".rb").camelize.scan(/[A-Z][a-z0-9]*/).first(2).join }
services.each do |f|
  text = src[f] or next
  next unless text.match?(/include Callable|^\s+def call\b|def self\.call\b/)
  klass = text[/^\s*class (\w+(::\w+)*)/, 1] or next
  siblings = services.select { |o| o != f && prefix[o] == prefix[f] && src[o].to_s.match?(/include Callable|^\s+def call\b/) }
  add.call(kind: "callable", id: "callable:#{klass}", file: f, line: 1,
    what: "#{text.lines.size} lines#{siblings.any? ? "; siblings: #{siblings.map { |s| File.basename(s, ".rb").camelize }.first(4).join(", ")}" : ""}",
    const: klass, churn_file: f)
end

# --- fat_job: jobs holding logic instead of delegating ----------------------------------------
Dir["app/jobs/**/*.rb"].each do |f|
  text = src[f] or next
  next if f.end_with?("application_job.rb")
  defs = text.scan(/^\s+def /).size
  next unless text.lines.size > 60 && defs >= 3
  klass = text[/^\s*class (\w+(::\w+)*)/, 1] or next
  add.call(kind: "fat_job", id: "fat_job:#{klass}", file: f, line: 1,
    what: "#{text.lines.size} lines, #{defs} methods", const: klass, churn_file: f)
end

# --- locals: partials without strict locals, one target per view folder ----------------------
Dir["app/views/**/_*.erb"].reject { |f| src[f].to_s.lines.first.to_s.include?("locals:") }
  .group_by { |f| File.dirname(f) }.each do |dir, files|
    next if dir.include?("/layouts") || dir.include?("/mailer")
    add.call(kind: "locals", id: "locals:#{dir}", file: dir, line: nil,
      what: "#{files.size} partials without `<%# locals: %>`", const: nil, churn_file: files)
  end

# --- route: custom member/collection actions -------------------------------------------------
routes = src["config/routes.rb"].to_s.lines
stack, in_custom = [], nil
routes.each_with_index do |l, i|
  stack << $1 if l =~ /^\s*resources? :(\w+)/ && l.include?(" do")
  in_custom = $1 if l =~ /^\s*(member|collection) do/
  if in_custom && l =~ /^\s*(get|post|patch|put|delete) :(\w+)/
    res = stack.last || "?"
    add.call(kind: "route", id: "route:#{res}##{$2}", file: "config/routes.rb", line: i + 1,
      what: "#{in_custom} #{$1} :#{$2} on #{res}", const: nil, churn_file: "config/routes.rb")
  end
  in_custom = nil if in_custom && l =~ /^\s*end\b/ && l[/^\s*/].size <= 6
end

# --- unique_index: uniqueness validations with no matching unique index ----------------------
schema = File.exist?("db/schema.rb") ? File.read("db/schema.rb") : ""
uniq_idx = Hash.new { |h, k| h[k] = [] }
current = nil
schema.each_line do |l|
  current = $1 if l =~ /^\s*create_table "(\w+)"/
  # Partial indexes count only in the `col IS NOT NULL` form, which matches `allow_nil` validations.
  where = l[/where: "(.*)"\s*$/, 1]
  next unless current && l.include?("unique: true") && (where.nil? || where.match?(/\A\(?\(?\w+ IS NOT NULL\)?\)?\z/))
  if l =~ /t\.index \[([^\]]+)\]/
    uniq_idx[current] << $1.scan(/"(\w+)"/).flatten.sort
  elsif l =~ /t\.index "([^"]+)"/ # expression index, e.g. lower((name)::text)
    uniq_idx[current] << $1.scan(/\((\w+)\)::/).flatten.sort
  end
  if l =~ /add_index "(\w+)", \[([^\]]+)\].*unique: true/
    uniq_idx[$1] << $2.scan(/"(\w+)"/).flatten.sort
  end
end
model_files.each do |f|
  text = src[f] or next
  klass = text[/^\s*class (\w+(::\w+)*)/, 1] or next
  table = text[/self\.table_name\s*=\s*"(\w+)"/, 1] || klass.demodulize.underscore.pluralize
  text.scan(/^\s*validates?\s+:(\w+)[^\n]*uniqueness:\s*(\{[^\n]*\}|true)/).each do |col, opt|
    scope = opt.to_s[/scope:\s*\[?([^\]\}]+)/, 1].to_s.scan(/:(\w+)/).flatten
    cols = ([col] + scope).sort
    # A unique index on a subset of the validated columns is stricter, so it covers the rule.
    next if uniq_idx[table].any? { |idx| idx.any? && (idx - cols).empty? }
    add.call(kind: "unique_index", id: "unique_index:#{klass}.#{cols.join("+")}", file: f, line: nil,
      what: "validates uniqueness of #{cols.join(", ")} on #{table} with no unique index", const: klass, churn_file: f)
  end
end

# --- ledger, scoring, output -----------------------------------------------------------------
closed = {}
if File.exist?(opts[:ledger])
  File.foreach(opts[:ledger]) do |l|
    e = JSON.parse(l) rescue next
    closed[e["id"]] = e["status"]
  end
end
fanin_cache = {}
targets.each do |t|
  fi = t[:const] ? (fanin_cache[t[:const]] ||= fan_in(src, t[:const].split("::").last, t[:file])) : 1
  c = Array(t.delete(:churn_file)).sum { |p| churn[p] }
  t[:fan_in], t[:churn_180d] = fi, c
  t[:score] = ((1 + c) * (1 + fi / 25.0) * KIND_WEIGHT[t[:kind]]).round(1)
  t[:ledger] = closed[t[:id]]
end
if opts[:show]
  t = targets.find { |x| x[:id] == opts[:show] }
  puts(t ? JSON.pretty_generate(t) : "no target #{opts[:show]}")
  exit(t ? 0 : 1)
end
open_targets = targets.reject { |t| %w[pr_open merged skipped wontfix].include?(t[:ledger]) }
open_targets.select! { |t| opts[:kinds].include?(t[:kind]) } if opts[:kinds]
open_targets.select! { |t| t[:id].include?(opts[:only]) || t[:file].to_s.include?(opts[:only]) } if opts[:only]
open_targets.sort_by! { |t| -t[:score] }

puts "refactor-sweep inventory: #{open_targets.size} open targets (#{targets.size - open_targets.size} closed or filtered)"
puts open_targets.group_by { |t| t[:kind] }.map { |k, v| "  #{k.ljust(13)} #{v.size}" }.join("\n")
puts "\ntop #{opts[:top]}:"
open_targets.first(opts[:top]).each_with_index do |t, i|
  puts format("%3d. %6.1f  %-48s churn %-3d fan-in %-4d %s%s", i + 1, t[:score], t[:id][0, 48], t[:churn_180d], t[:fan_in],
    t[:what][0, 70], t[:ledger] ? "  [#{t[:ledger]}]" : "")
end
File.write(opts[:out], JSON.pretty_generate(open_targets)) if opts[:out]
