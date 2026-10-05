#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-12: fails if a row of docs/security/release-audit.md has no evidence link, if a relative link
# does not resolve, or if an AC-01..AC-20 or docs/planning/decisions.md D-nn entry has no row.
#
#   ruby tools/ci/check_release_audit_checklist.rb                # check the real checklist
#   ruby tools/ci/check_release_audit_checklist.rb <checklist.md> [<decisions.md>]

module ReleaseAuditChecklist
  REPO_ROOT = File.expand_path('../..', __dir__)
  DEFAULT_CHECKLIST = File.join(REPO_ROOT, 'docs/security/release-audit.md')
  DEFAULT_DECISIONS = File.join(REPO_ROOT, 'docs/planning/decisions.md')
  ROW = /^\|\s*(\[[ x]\]|D-\d+)\s*\|/.freeze
  LINK = /\]\(([^)\s]+)\)/.freeze
  REQUIRED_ACS = (1..20).map { |n| format('AC-%02d', n) }.freeze

  module_function

  def check_links(checklist)
    File.readlines(checklist).each_with_index.flat_map do |line, index|
      next [] unless ROW.match?(line)

      targets = line.scan(LINK).flatten
      next ["#{checklist}:#{index + 1}: row has no evidence link: #{line.strip[0, 60]}"] if targets.empty?

      targets.filter_map { |target| unresolved_error(checklist, index + 1, target) }
    end
  end

  def check_coverage(checklist, decisions)
    text = File.read(checklist)
    missing = REQUIRED_ACS.reject { |ac| text.match?(/^\|[^|]*\|\s*#{ac}\b/) }
    missing += File.read(decisions).scan(/^\| (D-\d+) /).flatten.reject { |id| text.match?(/^\| #{id} \|/) }
    missing.map { |id| "#{checklist}: no checklist row for #{id}" }
  end

  def check(checklist = DEFAULT_CHECKLIST, decisions = DEFAULT_DECISIONS)
    check_links(checklist) + check_coverage(checklist, decisions)
  end

  def unresolved_error(checklist, line_number, target)
    return nil if target.match?(%r{\A(https?:|#)})

    path = File.expand_path(target.split('#').first, File.dirname(checklist))
    "#{checklist}:#{line_number}: link does not resolve: #{target}" unless File.exist?(path)
  end
end

if $PROGRAM_NAME == __FILE__
  errors = ReleaseAuditChecklist.check(*ARGV)
  errors.each { |e| warn e }
  puts "release audit checklist check: #{errors.empty? ? 'OK' : "#{errors.size} error(s)"}"
  exit(errors.empty? ? 0 : 1)
end
