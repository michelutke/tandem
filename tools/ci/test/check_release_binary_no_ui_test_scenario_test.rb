# frozen_string_literal: true

# ruby tools/ci/test/check_release_binary_no_ui_test_scenario_test.rb
#
# tdd (E00-26):
#   ci: releaseBinary_uiTestScenarioHook_stringAbsent

require 'minitest/autorun'
require_relative '../check_release_binary_no_ui_test_scenario'

class CheckReleaseBinaryNoUITestScenarioTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures', __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  def test_releaseBinary_uiTestScenarioHook_stringAbsent
    errors = ReleaseBinaryScenarioCheck.check(fixture('release_binary_clean.bin'))

    assert_empty errors
  end

  def test_releaseBinary_uiTestScenarioHookFixture_stringPresent_exitsNonZero
    errors = ReleaseBinaryScenarioCheck.check(fixture('release_binary_with_scenario_hook.bin'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('UITestScenario') }, "expected a UITestScenario error, got: #{errors.inspect}")
  end

  def test_releaseBinary_missingFile_exitsNonZero
    errors = ReleaseBinaryScenarioCheck.check(fixture('does-not-exist.bin'))

    refute_empty errors
  end
end
