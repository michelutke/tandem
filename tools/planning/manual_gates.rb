#!/usr/bin/env ruby
# frozen_string_literal: true

# Scaffolds docs/testing/manual-gates.md from every `manual:` tdd entry in docs/planning/backlog/*.yaml.
#
#   ruby tools/planning/manual_gates.rb          # append missing headings, print summary
#   ruby tools/planning/manual_gates.rb --write  # same (explicit)
#   ruby tools/planning/manual_gates.rb --check  # exit 1 listing any manual: entry without a heading,
#                                                 # and any heading whose backlog entry no longer exists
#
# Never edits or deletes an existing heading's body — filled-in procedures and sign-offs survive
# re-runs. A generated heading names the entry's test name, issue ID and phase, and carries that
# issue's acceptance criteria as reference for whoever writes the procedure.

require 'yaml'

ROOT = File.expand_path('../..', __dir__)
DOC = File.join(ROOT, 'docs/testing/manual-gates.md')
BACKLOG_GLOB = File.join(ROOT, 'docs/planning/backlog/phase-*.yaml')

ManualEntry = Struct.new(:test_name, :issue_id, :phase, :title, :acceptance, keyword_init: true)

HEADING = /^### (\S+) \(([^,]+), phase (\S+)\)/.freeze

def manual_entries
  Dir[BACKLOG_GLOB].sort.flat_map do |path|
    doc = YAML.load_file(path)
    Array(doc['epics']).flat_map do |e|
      Array(e['issues']).flat_map do |i|
        Array(i['tdd']).grep(/\Amanual: /).map do |entry|
          ManualEntry.new(
            test_name: entry.sub(/\Amanual: /, ''),
            issue_id: i['id'],
            phase: i['lands_in_phase'] || doc['phase'],
            title: i['title'],
            acceptance: Array(i['acceptance'])
          )
        end
      end
    end
  end
end

def heading_line(entry) = "### #{entry.test_name} (#{entry.issue_id}, phase #{entry.phase})"

def template_for(entry)
  ref = entry.acceptance.empty? ? "_none listed on #{entry.issue_id}_" : entry.acceptance.map { |a| "- #{a}" }.join("\n")
  <<~MD
    #{heading_line(entry)}

    #{entry.title}

    Reference — #{entry.issue_id} acceptance criteria:
    #{ref}

    **Preconditions:** _TBD_
    **Steps:** _TBD_
    **Pass threshold:** _TBD_
    **Evidence required (log excerpt / screen recording / pcap path):** _TBD_

    | Date | Build SHA | Device | Result |
    |---|---|---|---|
    | | | | |

  MD
end

DEFAULT_DOC = <<~MD
  # Manual test gates

  Physical-device sign-off log for every `manual:` tdd entry in `docs/planning/backlog/*.yaml`
  (see `docs/planning/README.md` → Test layers). Devices are listed in `docs/testing/device-matrix.md`.

  Scaffolded and checked by `ruby tools/planning/manual_gates.rb` (see header of that file for
  usage). The generator only appends missing headings below — it never edits or deletes one, so
  filled-in procedures and sign-off rows are safe. A phase exits only when every P0 `manual:` row
  for that phase is signed off.
MD

entries = manual_entries
text = File.exist?(DOC) ? File.read(DOC) : DEFAULT_DOC
present_names = text.scan(HEADING).map(&:first)
known_names = entries.map(&:test_name)

missing = entries.reject { |e| present_names.include?(e.test_name) }
orphaned = present_names - known_names

if ARGV.include?('--check')
  problems = missing.map { |e| "✗ manual: #{e.test_name} (#{e.issue_id}) has no heading in manual-gates.md" }
  problems += orphaned.map { |n| "✗ manual-gates.md heading #{n} has no matching manual: entry in the backlog" }
  abort(problems.join("\n")) unless problems.empty?
  puts "✓ manual-gates.md: #{entries.size} manual: entries, all have headings"
else
  unless missing.empty?
    text = "#{text.rstrip}\n\n#{missing.map { |e| template_for(e) }.join("\n")}"
    File.write(DOC, text)
  end
  puts "wrote #{missing.size} new heading(s); #{entries.size - missing.size} already present"
end
