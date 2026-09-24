#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-12: keeps CLAUDE.md honest.
#
#   ruby tools/planning/check_claude_md.rb                 # invariants + Testing section
#   ruby tools/planning/check_claude_md.rb --run-commands  # also run every line of the Commands block
#
# Fails if the eight security invariants differ from PRD <architecture>, if a tdd layer prefix
# from the backlog validator (TDD_LAYERS in sync_issues.rb) is missing from `## Testing`, or (with
# --run-commands) if any listed command exits non-zero.

require 'open3'

module CheckClaudeMd
  ROOT = File.expand_path('../..', __dir__)

  module_function

  def invariants(markdown, heading)
    section = markdown[/^## #{Regexp.escape(heading)}.*?\n(.*?)(?=^## |\z)/m, 1].to_s
    section.scan(/^\d+\.\s+(.+)$/).flatten.map(&:strip)
  end

  def tdd_layers(sync_issues_source)
    list = sync_issues_source[/TDD_LAYERS = %w\[([^\]]+)\]/, 1] or raise 'TDD_LAYERS not found'
    list.split
  end

  def commands(markdown)
    block = markdown[/^## Commands\n.*?```sh\n(.*?)```/m, 1].to_s
    block.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end

  def check(claude:, prd:, sync_issues:)
    errors = []
    expected = invariants(prd, 'Security invariants (copy into CLAUDE.md)')
    actual = invariants(claude, 'Security invariants')
    errors << "PRD lists #{expected.size} invariants, expected 8" unless expected.size == 8
    expected.each_with_index do |text, i|
      errors << "invariant #{i + 1} differs from PRD:\n  PRD:       #{text}\n  CLAUDE.md: #{actual[i].inspect}" unless actual[i] == text
    end
    errors << "CLAUDE.md lists #{actual.size} invariants, PRD #{expected.size}" if actual.size != expected.size
    testing = claude[/^## Testing\n(.*?)(?=^## |\z)/m, 1]
    if testing.nil?
      errors << 'CLAUDE.md has no `## Testing` section'
    else
      tdd_layers(sync_issues).each do |layer|
        errors << "`## Testing` does not describe the `#{layer}` layer" unless testing.match?(/^- `#{layer}` — /)
      end
    end
    errors
  end

  def run_commands(markdown, root: ROOT)
    commands(markdown).filter_map do |cmd|
      out, status = Open3.capture2e('bash', '-c', cmd, chdir: root)
      "command failed (exit #{status.exitstatus}): #{cmd}\n#{out.lines.last(20).join}" unless status.success?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = CheckClaudeMd::ROOT
  claude = File.read(File.join(root, 'CLAUDE.md'))
  errors = CheckClaudeMd.check(claude: claude, prd: File.read(File.join(root, 'docs/PRD.md')),
                               sync_issues: File.read(File.join(root, 'tools/planning/sync_issues.rb')))
  errors += CheckClaudeMd.run_commands(claude) if ARGV.include?('--run-commands')
  if errors.empty?
    puts 'CLAUDE.md check: OK'
  else
    warn "CLAUDE.md check: FAILED\n\n#{errors.join("\n\n")}"
    exit 1
  end
end
