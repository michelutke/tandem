#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates docs/planning/backlog/*.yaml and syncs it to GitHub issues.
#
#   ruby tools/planning/sync_issues.rb validate        # schema, refs, cycles
#   ruby tools/planning/sync_issues.rb render          # writes docs/planning/BACKLOG.md
#   ruby tools/planning/sync_issues.rb sync [--dry-run] [--link-deps] # labels, milestones, issues, sub-issues
#     --link-deps also creates native blocked-by links (slow: GitHub write rate limits)
#
# Idempotent: every issue body carries `<!-- tandem-id: X -->`; existing issues are updated.
# Requires `gh` authenticated with repo scope. Repo from $TANDEM_REPO or `gh repo view`.

require 'yaml'
require 'json'
require 'open3'
require 'tsort'

ROOT = File.expand_path('../..', __dir__)
BACKLOG_GLOB = File.join(ROOT, 'docs/planning/backlog/phase-*.yaml')
USE_CASES = File.join(ROOT, 'docs/planning/use-cases.md')
PRD = File.join(ROOT, 'docs/PRD.md')

TYPES = %w[story task spike adr test doc].freeze
PLATFORMS = %w[android macos protocol tools docs ci].freeze
PRIORITIES = %w[P0 P1 P2].freeze
SIZES = %w[S M L].freeze

PHASES = {
  0 => 'Phase 0 — Foundations',
  1 => 'Phase 1 — Identity, pairing, secure transport',
  2 => 'Phase 2 — Lifecycle and reliability',
  3 => 'Phase 3 — Notifications and clipboard',
  4 => 'Phase 4 — Files and photos',
  5 => 'Phase 5 — Messaging, contacts, calls',
  6 => 'Phase 6 — Mirroring and remote input',
  7 => 'Phase 7 — Extras and hardening'
}.freeze

LABEL_COLORS = {
  'type:' => '5319e7', 'platform:' => '0e8a16', 'priority:P0' => 'b60205',
  'priority:P1' => 'fbca04', 'priority:P2' => 'c5def5', 'size:' => 'bfdadc',
  'area:' => '1d76db', 'invariant:' => 'd93f0b'
}.freeze

DOD = <<~MD
  - [ ] Failing tests written first, then made green
  - [ ] Acceptance criteria met
  - [ ] Conformance vectors pass on both platforms (if protocol/crypto touched)
  - [ ] Lint clean (ktlint, detekt / SwiftLint / buf lint)
  - [ ] Security invariants listed above re-checked; no logging of secrets or content
  - [ ] Docs updated (SPEC.md / ADR / CLAUDE.md) where behaviour changed
  - [ ] CI green
MD

class Graph
  include TSort

  def initialize(edges) = @edges = edges
  def tsort_each_node(&) = @edges.each_key(&)
  def tsort_each_child(node, &) = @edges.fetch(node, []).each(&)
end

def load_backlog
  Dir[BACKLOG_GLOB].sort.flat_map do |path|
    doc = YAML.load_file(path)
    Array(doc['epics']).map { |e| e.merge('phase' => doc['phase'], '_file' => File.basename(path)) }
  end
end

def known_ids(path, pattern) = File.read(path).scan(pattern).flatten.uniq

def validate(epics)
  errors = []
  uc_ids = known_ids(USE_CASES, /\b((?:UC|AC)-\d{2})\b/)
  prd_ids = known_ids(PRD, /\b(F-\d+\.\d+)\b/)
  issues = epics.flat_map { |e| Array(e['issues']).map { |i| i.merge('epic' => e['id']) } }
  ids = (epics.map { |e| e['id'] } + issues.map { |i| i['id'] })
  ids.tally.each { |id, n| errors << "duplicate id #{id}" if n > 1 }
  issue_ids = issues.map { |i| i['id'] }

  epics.each do |e|
    errors << "#{e['id']}: phase missing/invalid" unless PHASES.key?(e['phase'])
    %w[title summary exit_criteria issues].each { |k| errors << "#{e['id']}: missing #{k}" if blank?(e[k]) }
    check_refs(errors, e['id'], e, uc_ids, prd_ids)
  end

  issues.each do |i|
    id = i['id']
    errors << "#{id}: id must start with #{i['epic']}-" unless id.to_s.start_with?("#{i['epic']}-")
    %w[title description acceptance].each { |k| errors << "#{id}: missing #{k}" if blank?(i[k]) }
    errors << "#{id}: bad type #{i['type']}" unless TYPES.include?(i['type'])
    errors << "#{id}: bad priority" unless PRIORITIES.include?(i['priority'])
    errors << "#{id}: bad size" unless SIZES.include?(i['size'])
    Array(i['platforms']).each { |p| errors << "#{id}: bad platform #{p}" unless PLATFORMS.include?(p) }
    Array(i['invariants']).each { |n| errors << "#{id}: bad invariant #{n}" unless (1..8).cover?(n) }
    if %w[story task test].include?(i['type']) && blank?(i['tdd'])
      errors << "#{id}: story/task/test needs tdd entries"
    end
    check_tdd(errors, id, i)
    Array(i['depends_on']).each { |d| errors << "#{id}: unknown dependency #{d}" unless issue_ids.include?(d) }
    check_refs(errors, id, i, uc_ids, prd_ids)
  end

  epic_phase = epics.to_h { |e| [e['id'], e['phase']] }
  issues.each do |i|
    next unless i.key?('lands_in_phase')
    next if PHASES.key?(i['lands_in_phase']) && i['lands_in_phase'] > epic_phase[i['epic']].to_i

    errors << "#{i['id']}: lands_in_phase must be a phase after its epic's (#{epic_phase[i['epic']]})"
  end
  phase_of = issues.to_h { |i| [i['id'], effective_phase(i, epic_phase[i['epic']])] }
  priority_of = issues.to_h { |i| [i['id'], i['priority']] }
  issues.each do |i|
    Array(i['depends_on']).each do |d|
      if phase_of[d] && phase_of[d] > phase_of[i['id']]
        errors << "#{i['id']} (phase #{phase_of[i['id']]}) depends on later-phase #{d} (phase #{phase_of[d]})"
      end
      if priority_of[d].to_s > priority_of[i['id']].to_s
        errors << "#{i['id']} (#{i['priority']}) depends on lower-priority #{d} (#{priority_of[d]})"
      end
    end
  end

  begin
    Graph.new(issues.to_h { |i| [i['id'], Array(i['depends_on']) & issue_ids] }).tsort
  rescue TSort::Cyclic => e
    errors << "dependency cycle: #{e.message}"
  end
  [errors, issues]
end

# `layer: unit_condition_expectedResult` — see backlog/SCHEMA.md for the layer list.
TDD_LAYERS = %w[unit conformance integration instrumented ui manual security ci].freeze
TDD_FORMAT = /\A(#{TDD_LAYERS.join('|')}): [a-z][A-Za-z0-9]*_[a-z][A-Za-z0-9]*_[a-z][A-Za-z0-9]*\z/

def check_tdd(errors, id, issue)
  tdd = Array(issue['tdd'])
  tdd.each { |t| errors << "#{id}: tdd entry not `layer: unit_condition_expected`: #{t}" unless TDD_FORMAT.match?(t.to_s) }
  tdd.tally.each { |t, n| errors << "#{id}: duplicate tdd entry #{t}" if n > 1 }
  case issue['type']
  when 'spike', 'adr'
    errors << "#{id}: #{issue['type']} must have tdd: [] (put deliverable in acceptance)" unless tdd.empty?
  when 'doc'
    tdd.each { |t| errors << "#{id}: doc tdd entries must be automated ci: checks: #{t}" unless t.to_s.start_with?('ci: ') }
  end
end

def check_refs(errors, id, obj, uc_ids, prd_ids)
  Array(obj['use_cases']).each { |u| errors << "#{id}: unknown use case #{u}" unless uc_ids.include?(u) }
  Array(obj['prd']).each { |f| errors << "#{id}: unknown PRD ref #{f}" unless prd_ids.include?(f) }
end

# An issue stays in its epic (IDs are epic-bound) but may land at the start of a later phase.
def effective_phase(issue, epic_phase) = issue['lands_in_phase'] || epic_phase

def blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?)

def labels_for_issue(issue, epic)
  ["type:#{issue['type']}", "priority:#{issue['priority']}", "size:#{issue['size']}"] +
    Array(issue['platforms']).map { |p| "platform:#{p}" } +
    Array(issue['invariants']).map { |n| "invariant:#{n}" } +
    Array(epic['labels'])
end

def labels_for_epic(epic) = ['type:epic'] + Array(epic['labels'])

def checklist(items) = Array(items).map { |x| "- [ ] #{x}" }.join("\n")
def bullets(items) = Array(items).map { |x| "- #{x}" }.join("\n")
def refs(obj) = (Array(obj['prd']) + Array(obj['use_cases'])).join(', ')

def ref_issue(id, numbers) = numbers[id] ? "##{numbers[id]} (#{id})" : id

def epic_body(epic, issues, numbers)
  <<~MD
    <!-- tandem-id: #{epic['id']} -->
    #{epic['summary'].to_s.strip}

    **Phase:** #{epic['phase']} · **Refs:** #{refs(epic)} · Source: `docs/planning/backlog/#{epic['_file']}`

    ### Scope
    #{bullets(epic['scope'])}

    ### Out of scope
    #{bullets(epic['out_of_scope'])}

    ### Exit criteria
    #{checklist(epic['exit_criteria'])}

    ### Issues
    #{issues.map { |i| "- [ ] #{ref_issue(i['id'], numbers)} #{i['title']}" }.join("\n")}
  MD
end

def issue_body(issue, epic, numbers)
  deps = Array(issue['depends_on'])
  tdd = Array(issue['tdd'])
  inv = Array(issue['invariants'])
  <<~MD
    <!-- tandem-id: #{issue['id']} -->
    **Epic:** #{ref_issue(epic['id'], numbers)} #{epic['title']} · **Type:** #{issue['type']} · **Priority:** #{issue['priority']} · **Size:** #{issue['size']}#{issue['lands_in_phase'] ? " · **Lands:** start of Phase #{issue['lands_in_phase']}" : ''}
    **Refs:** #{refs(issue).then { |r| r.empty? ? '—' : r }} · **Security invariants:** #{inv.empty? ? '—' : inv.join(', ')}
    **Blocked by:** #{deps.empty? ? '—' : deps.map { |d| ref_issue(d, numbers) }.join(', ')}

    ### Description
    #{issue['description'].to_s.strip}

    ### Acceptance criteria
    #{checklist(issue['acceptance'])}
    #{tdd.empty? ? '' : "\n### TDD — write these failing tests first\n#{checklist(tdd.map { |t| "`#{t}`" })}\n"}
    #{issue['notes'] ? "### Notes\n#{issue['notes'].to_s.strip}\n" : ''}
    ### Definition of Done
    #{DOD}
  MD
end

def render_markdown(epics)
  out = +"# Tandem backlog (generated — edit `backlog/*.yaml`, run `sync_issues.rb render`)\n\n"
  epics.group_by { |e| e['phase'] }.sort.each do |phase, list|
    out << "## #{PHASES[phase]}\n\n"
    list.each do |e|
      out << "### #{e['id']} — #{e['title']}\n\n#{e['summary'].to_s.strip}\n\n"
      out << "**Exit criteria**\n\n#{checklist(e['exit_criteria'])}\n\n"
      out << "| ID | Title | Type | Pri | Size | Depends on |\n|---|---|---|---|---|---|\n"
      Array(e['issues']).each do |i|
        lands = i['lands_in_phase'] ? " *(lands Phase #{i['lands_in_phase']})*" : ''
        out << "| #{i['id']} | #{i['title'].to_s.gsub('|', '\\|')}#{lands} | #{i['type']} | #{i['priority']} | " \
               "#{i['size']} | #{Array(i['depends_on']).join(', ')} |\n"
      end
      out << "\n"
    end
  end
  totals = epics.flat_map { |e| Array(e['issues']) }
  out << "---\n\n**Totals:** #{epics.size} epics, #{totals.size} issues " \
         "(#{totals.map { |i| i['priority'] }.tally.sort.map { |k, v| "#{k}: #{v}" }.join(', ')})\n"
  File.write(File.join(ROOT, 'docs/planning/BACKLOG.md'), out)
  puts "wrote docs/planning/BACKLOG.md (#{epics.size} epics, #{totals.size} issues)"
end

# --- GitHub ---------------------------------------------------------------

class GitHub
  def initialize(dry_run:)
    @dry = dry_run
    @repo = ENV['TANDEM_REPO'] || run(%w[gh repo view --json nameWithOwner -q .nameWithOwner]).strip
  end

  attr_reader :repo

  def run(args, input: nil, allow_fail: false)
    out, err, status = Open3.capture3(*args, stdin_data: input)
    raise "#{args.join(' ')} failed: #{err}" unless status.success? || allow_fail

    status.success? ? out : nil
  end

  # GitHub caps content-creating requests (~80/min, ~500/h); pace writes and back off on 403/429.
  WRITE_INTERVAL = Float(ENV.fetch('TANDEM_WRITE_INTERVAL', '7.5'))
  
  def api(method, path, body = nil, allow_fail: false)
    return '{}' if @dry && method != 'GET'
  
    args = ['gh', 'api', '-X', method, path, '-H', 'Accept: application/vnd.github+json']
    args += ['--input', '-'] if body
    return run(args, input: body&.to_json, allow_fail: allow_fail) if method == 'GET'
  
    write(args, body, allow_fail)
  end
  
  def write(args, body, allow_fail)
    5.times do |attempt|
      sleep [(@last_write || 0) + WRITE_INTERVAL - Time.now.to_f, 0].max
      out, err, status = Open3.capture3(*args, stdin_data: body&.to_json)
      @last_write = Time.now.to_f
      return out if status.success?
  
      unless err.match?(/rate limit|HTTP 403|HTTP 429|HTTP 50\d/i)
        return nil if allow_fail
  
        raise "#{args.join(' ')} failed: #{err}"
      end
      wait = 60 * (2**attempt)
      warn "rate limited, waiting #{wait}s: #{err.lines.first&.strip}"
      sleep wait
    end
    raise "#{args.join(' ')} failed after retries"
  end
  
  def max_issue_number
    JSON.parse(run(['gh', 'api', "repos/#{repo}/issues?state=all&per_page=1&sort=created&direction=desc"]))
        .first&.fetch('number') || 0
  end
  
  def sub_issue_numbers(number)
    paginate("repos/#{repo}/issues/#{number}/sub_issues?per_page=100").map { |i| i['number'] }
  end

  def paginate(path) = JSON.parse(run(['gh', 'api', '--paginate', '--slurp', path])).flatten

  def ensure_labels(names)
    existing = paginate("repos/#{repo}/labels?per_page=100").map { |l| l['name'] }
    (names.uniq - existing).each do |name|
      color = LABEL_COLORS.find { |prefix, _| name.start_with?(prefix) }&.last || 'ededed'
      puts "label + #{name}"
      api('POST', "repos/#{repo}/labels", { name: name, color: color })
    end
  end

  def ensure_milestones
    existing = paginate("repos/#{repo}/milestones?state=all&per_page=100").to_h { |m| [m['title'], m['number']] }
    PHASES.values.to_h do |title|
      next [title, existing[title]] if existing[title]

      puts "milestone + #{title}"
      [title, JSON.parse(api('POST', "repos/#{repo}/milestones", { title: title }))['number']]
    end
  end

  def existing_issues
    paginate("repos/#{repo}/issues?state=all&per_page=100")
      .reject { |i| i['pull_request'] }
      .filter_map { |i| (m = i['body'].to_s.match(/tandem-id: (\S+) -->/)) && [m[1], i] }
      .to_h
  end
end

def render_item(id, obj, epic, issues, numbers, milestones)
  phase = epic ? effective_phase(obj, epic['phase']) : obj['phase']
  if epic
    { title: "#{id} #{obj['title']}", body: issue_body(obj, epic, numbers),
      labels: labels_for_issue(obj, epic), milestone: milestones[PHASES[phase]] }
  else
    { title: "#{id} · #{obj['title']}", body: epic_body(obj, issues.select { |i| i['epic'] == id }, numbers),
      labels: labels_for_epic(obj), milestone: milestones[PHASES[phase]] }
  end
end

def unchanged?(current, payload)
  current['title'] == payload[:title] && current['body'].to_s.strip == payload[:body].strip &&
    current['labels'].map { |l| l['name'] }.sort == payload[:labels].uniq.sort &&
    current.dig('milestone', 'number') == payload[:milestone]
end

# Issue numbers are predicted (next free number, in creation order) so each issue is created
# with its final body in one request; a mismatch falls back to a PATCH pass.
def sync(epics, issues, dry_run:, link_deps:)
  gh = GitHub.new(dry_run: dry_run)
  puts "repo: #{gh.repo}#{' (dry run)' if dry_run}"
  epic_by_id = epics.to_h { |e| [e['id'], e] }
  gh.ensure_labels(epics.flat_map { |e| labels_for_epic(e) } +
                   issues.flat_map { |i| labels_for_issue(i, epic_by_id[i['epic']]) })
  milestones = gh.ensure_milestones
  existing = gh.existing_issues
  numbers = existing.transform_values { |i| i['number'] }
  db_ids = existing.transform_values { |i| i['id'] }
  items = epics.map { |e| [e['id'], e, nil] } + issues.map { |i| [i['id'], i, epic_by_id[i['epic']]] }

  next_number = gh.max_issue_number + 1
  missing = items.reject { |id, _, _| numbers[id] }
  missing.each_with_index { |(id, _, _), n| numbers[id] = next_number + n }

  stale = []
  missing.each do |id, obj, epic|
    payload = render_item(id, obj, epic, issues, numbers, milestones)
    res = JSON.parse(gh.api('POST', "repos/#{gh.repo}/issues", payload))
    next puts("create #{payload[:title]}") if dry_run

    if res['number'] != numbers[id]
      warn "#{id}: expected ##{numbers[id]}, got ##{res['number']}; will re-render"
      numbers[id] = res['number']
      stale << id
    end
    db_ids[id] = res['id']
    puts "create ##{res['number']} #{payload[:title]}"
  end

  items.each do |id, obj, epic|
    next unless existing[id] || !stale.empty?

    payload = render_item(id, obj, epic, issues, numbers, milestones)
    next if existing[id] && unchanged?(existing[id], payload)

    gh.api('PATCH', "repos/#{gh.repo}/issues/#{numbers[id]}", payload)
    puts "update ##{numbers[id]} #{id}"
  end
  return if dry_run

  link_sub_issues(gh, epics, issues, numbers, db_ids)
  link_dependencies(gh, issues, numbers, db_ids) if link_deps
end

def link_sub_issues(gh, epics, issues, numbers, db_ids)
  epics.each do |e|
    linked = gh.sub_issue_numbers(numbers[e['id']])
    issues.select { |i| i['epic'] == e['id'] }.each do |i|
      next if linked.include?(numbers[i['id']])

      gh.api('POST', "repos/#{gh.repo}/issues/#{numbers[e['id']]}/sub_issues",
             { sub_issue_id: db_ids[i['id']] }, allow_fail: true)
    end
    puts "sub-issues linked for #{e['id']}"
  end
end

# ~1300 edges; at the secondary rate limit this takes hours, so it is opt-in (--link-deps).
# Issue bodies already list "Blocked by #n" for every dependency.
def link_dependencies(gh, issues, numbers, db_ids)
  issues.each do |i|
    Array(i['depends_on']).each do |d|
      gh.api('POST', "repos/#{gh.repo}/issues/#{numbers[i['id']]}/dependencies/blocked_by",
             { issue_id: db_ids[d] }, allow_fail: true)
    end
  end
  puts 'linked blocked-by dependencies'
end

command = ARGV.first || 'validate'
epics = load_backlog
errors, issues = validate(epics)
unless errors.empty?
  warn errors.map { |e| "✗ #{e}" }.join("\n")
  warn "#{errors.size} error(s)"
  exit 1
end
puts "✓ #{epics.size} epics, #{issues.size} issues valid"

case command
when 'validate' then nil
when 'render' then render_markdown(epics)
when 'sync' then sync(epics, issues, dry_run: ARGV.include?('--dry-run'), link_deps: ARGV.include?('--link-deps'))
else abort "unknown command #{command}"
end
