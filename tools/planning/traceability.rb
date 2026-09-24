#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates the machine-derived tables in docs/planning/traceability.md and checks that every
# issue ID cited anywhere in that file exists in the backlog.
#
#   ruby tools/planning/traceability.rb          # rewrite generated sections, then check
#   ruby tools/planning/traceability.rb --check  # check only (non-zero exit on stale/unknown IDs)
#
# Generated sections sit between `<!-- BEGIN GENERATED: name -->` and `<!-- END GENERATED: name -->`.
# Everything else in traceability.md is hand-curated mapping judgment.

require 'yaml'

ROOT = File.expand_path('../..', __dir__)
DOC = File.join(ROOT, 'docs/planning/traceability.md')
PRD = File.join(ROOT, 'docs/PRD.md')
USE_CASES = File.join(ROOT, 'docs/planning/use-cases.md')

# Scope judgment per PRD feature (only non-default entries; default is "v1").
FEATURE_STATUS = {
  'F-2.2' => 'deferred (v2+): ADR E73-01; implementation P2, gated (E73-02..E73-05)',
  'F-6.2' => 'v1; accessibility auto-capture is ADR-only, off by default (E31-09)',
  'F-7.5' => 'out of scope v1 (PRD marks v2); recorded in E40 out_of_scope, no issue',
  'F-8.1' => 'v1 text SMS; MMS deferred to v2, scope spike E50-12 (Appendix C.4)',
  'F-8.4' => 'v1; call log view deferred to v2 (E52 out_of_scope)',
  'F-9.4' => 'ADR-decided: options E02-07, decision E61-10; implementation P2, gated (E62-10)',
  'F-10.1' => 'v2+/P2: design note E72-01 gates E72-02',
  'F-10.2' => 'v2+/P2: design note E72-03 gates E72-04',
  'F-10.3' => 'v2+/P2: design spike E72-05 gates E72-06',
  'F-10.4' => 'out of scope v1: ADR only (E72-07, Appendix C.2); implementation is a future epic'
}.freeze

def issues
  @issues ||= Dir[File.join(ROOT, 'docs/planning/backlog/phase-*.yaml')].sort.flat_map do |path|
    Array(YAML.load_file(path)['epics']).flat_map { |e| Array(e['issues']) }
  end
end

def ordered(ids) = ids.uniq.sort_by { |id| id.scan(/\d+/).map(&:to_i) }

def refs_for(field, id) = issues.select { |i| Array(i[field]).include?(id) }.map { |i| i['id'] }

def features_table
  ids = ordered(File.read(PRD).scan(/\bF-\d+\.\d+\b/))
  rows = ids.map do |f|
    refs = refs_for('prd', f)
    "| #{f} | #{FEATURE_STATUS.fetch(f, 'v1')} | #{refs.empty? ? '—' : refs.join(', ')} |"
  end
  ['| Feature | Scope | Issues citing it (`prd:`) |', '|---|---|---|', *rows].join("\n")
end

def use_cases_table
  ids = File.read(USE_CASES).scan(/\b(?:UC|AC)-\d{2}\b/).uniq.sort
  rows = ids.map do |u|
    refs = refs_for('use_cases', u)
    "| #{u} | #{refs.size} | #{refs.empty? ? '**none**' : refs.join(', ')} |"
  end
  ['| ID | Count | Issues citing it (`use_cases:`) |', '|---|---|---|', *rows].join("\n")
end

GENERATORS = { 'features' => :features_table, 'use-cases' => :use_cases_table }.freeze

def regenerate(text)
  GENERATORS.reduce(text) do |acc, (name, gen)|
    pattern = /(<!-- BEGIN GENERATED: #{name} -->\n).*?(<!-- END GENERATED: #{name} -->)/m
    raise "missing generated section #{name}" unless acc.match?(pattern)

    acc.sub(pattern) { "#{Regexp.last_match(1)}#{send(gen)}\n#{Regexp.last_match(2)}" }
  end
end

def unknown_ids(text)
  known = issues.map { |i| i['id'] }
  text.scan(/\bE\d{2}-\d{2}\b/).uniq.reject { |id| known.include?(id) }
end

text = File.read(DOC)
fresh = regenerate(text)
if ARGV.include?('--check')
  abort('✗ generated sections are stale; run without --check') unless fresh == text
else
  File.write(DOC, fresh)
end
missing = unknown_ids(fresh)
abort("✗ unknown issue IDs cited: #{missing.join(', ')}") unless missing.empty?
puts "✓ traceability.md: #{issues.size} issues, all cited IDs exist"
