#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates docs/planning/backlog/*.yaml and syncs it to GitHub issues.
#
#   ruby tools/planning/sync_issues.rb validate        # schema, refs, cycles
#   ruby tools/planning/sync_issues.rb render          # writes docs/planning/BACKLOG.md
#   ruby tools/planning/sync_issues.rb sync [--dry-run] # labels, milestones, issues, sub-issues, deps
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
    if %w[story task].include?(i['type']) && blank?(i['tdd'])
      errors << "#{id}: story/task needs tdd entries"
    end
    Array(i['depends_on']).each { |d| errors << "#{id}: unknown dependency #{d}" unless issue_ids.include?(d) }
    check_refs(errors, id, i, uc_ids, prd_ids)
  end

  phase_of = issues.to_h { |i| [i['id'], epics.find { |e| e['id'] == i['epic'] }['phase']] }
  issues.each do |i|
    Array(i['depends_on']).each do |d|
      next unless phase_of[d] && phase_of[d] > phase_of[i['id']]

      errors << "#{i['id']} (phase #{phase_of[i['id']]}) depends on later-phase #{d} (phase #{phase_of[d]})"
    end
  end

  begin
    Graph.new(issues.to_h { |i| [i['id'], Array(i['depends_on']) & issue_ids] }).tsort
  rescue TSort::Cyclic => e
    errors << "dependency cycle: #{e.message}"
  end
  [errors, issues]
end

def check_refs(errors, id, obj, uc_ids, prd_ids)
  Array(obj['use_cases']).each { |u| errors << "#{id}: unknown use case #{u}" unless uc_ids.include?(u) }
  Array(obj['prd']).each { |f| errors << "#{id}: unknown PRD ref #{f}" unless prd_ids.include?(f) }
end

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
    **Epic:** #{ref_issue(epic['id'], numbers)} #{epic['title']} · **Type:** #{issue['type']} · **Priority:** #{issue['priority']} · **Size:** #{issue['size']}
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
        out << "| #{i['id']} | #{i['title'].to_s.gsub('|', '\\|')} | #{i['type']} | #{i['priority']} | " \
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

  def api(method, path, body = nil, allow_fail: false)
    return '{}' if @dry && method != 'GET'

    args = ['gh', 'api', '-X', method, path, '-H', 'Accept: application/vnd.github+json']
    args += ['--input', '-'] if body
    run(args, input: body&.to_json, allow_fail: allow_fail)
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

def sync(epics, issues, dry_run:)
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

  # Pass 1: create missing issues with a stub body so every ID has a number.
  items.each do |id, obj, _|
    next if numbers[id]

    title = obj['issues'] ? "#{id} · #{obj['title']}" : "#{id} #{obj['title']}"
    puts "create #{title}"
    res = JSON.parse(gh.api('POST', "repos/#{gh.repo}/issues",
                            { title: title, body: "<!-- tandem-id: #{id} -->" }))
    numbers[id] = res['number'] || "dry-#{id}"
    db_ids[id] = res['id']
    sleep 1 unless dry_run
  end

  # Pass 2: full bodies, labels, milestones.
  items.each do |id, obj, epic|
    phase = (epic || obj)['phase']
    body, labels, title =
      if epic
        [issue_body(obj, epic, numbers), labels_for_issue(obj, epic), "#{id} #{obj['title']}"]
      else
        [epic_body(obj, issues.select { |i| i['epic'] == id }, numbers), labels_for_epic(obj), "#{id} · #{obj['title']}"]
      end
    gh.api('PATCH', "repos/#{gh.repo}/issues/#{numbers[id]}",
           { title: title, body: body, labels: labels, milestone: milestones[PHASES[phase]] })
    puts "update ##{numbers[id]} #{id}"
  end

  return if dry_run

  # Pass 3: sub-issues and blocked-by relations (best effort; skip if already linked).
  issues.each do |i|
    gh.api('POST', "repos/#{gh.repo}/issues/#{numbers[i['epic']]}/sub_issues",
           { sub_issue_id: db_ids[i['id']] }, allow_fail: true)
    Array(i['depends_on']).each do |d|
      gh.api('POST', "repos/#{gh.repo}/issues/#{numbers[i['id']]}/dependencies/blocked_by",
             { issue_id: db_ids[d] }, allow_fail: true)
    end
  end
  puts 'linked sub-issues and dependencies'
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
when 'sync' then sync(epics, issues, dry_run: ARGV.include?('--dry-run'))
else abort "unknown command #{command}"
end
