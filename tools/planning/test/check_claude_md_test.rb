# frozen_string_literal: true

# E00-12 tdd:
#   ci: claudeMdCheck_invariantWordingDiffersFromPrd_exitsNonZero
#   ci: claudeMdCheck_layerPrefixMissingFromTestingSection_exitsNonZero
#   ci: claudeMdCommands_eachListedCommand_exitsZero (the real run is `--run-commands`; here the
#       runner is exercised against fixture commands)

require 'minitest/autorun'
require 'tmpdir'
require_relative '../check_claude_md'

class CheckClaudeMdTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)

  def setup
    @claude = File.read(File.join(ROOT, 'CLAUDE.md'))
    @prd = File.read(File.join(ROOT, 'docs/PRD.md'))
    @sync = File.read(File.join(ROOT, 'tools/planning/sync_issues.rb'))
  end

  def check(claude) = CheckClaudeMd.check(claude: claude, prd: @prd, sync_issues: @sync)

  def test_claudeMdCheck_currentRepo_passes
    assert_empty check(@claude)
  end

  def test_claudeMdCheck_invariantWordingDiffersFromPrd_exitsNonZero
    edited = @claude.sub('fails closed with a visible error', 'fails closed')
    errors = check(edited)
    assert(errors.any? { |e| e.include?('invariant 5 differs') }, errors.inspect)
  end

  def test_claudeMdCheck_layerPrefixMissingFromTestingSection_exitsNonZero
    edited = @claude.sub(/^- `security` — .*\n/, '')
    errors = check(edited)
    assert(errors.any? { |e| e.include?('`security` layer') }, errors.inspect)
  end

  def test_claudeMdCommands_eachListedCommand_exitsZero
    ok = "## Commands\n\n```sh\ntrue\nexit 0\n```\n"
    bad = "## Commands\n\n```sh\ntrue\nfalse\n```\n"
    Dir.mktmpdir do |dir|
      assert_empty CheckClaudeMd.run_commands(ok, root: dir)
      assert_equal 1, CheckClaudeMd.run_commands(bad, root: dir).size
    end
  end
end
