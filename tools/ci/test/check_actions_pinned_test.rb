# frozen_string_literal: true

# E00-29 tdd:
#   ci: githubActions_unpinnedActionRef_checkFails

require 'minitest/autorun'
require_relative '../check_actions_pinned'

class CheckActionsPinnedTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/actions-pinned', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def test_actionsPinCheck_realRepoWorkflows_exitsZero
    errors = ActionsPinned.check(File.join(REPO_ROOT, '.github', 'workflows'))

    assert_empty errors
  end

  def test_githubActions_unpinnedActionRef_checkFails
    errors = ActionsPinned.check_file(File.join(FIXTURES, 'unpinned-tag.yml'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('actions/checkout@v4') },
           "expected an unpinned-ref error, got: #{errors.inspect}")
  end

  def test_actionsPinCheck_pinnedShaAndLocalComposite_exitsZero
    errors = ActionsPinned.check_file(File.join(FIXTURES, 'pinned.yml'))

    assert_empty errors
  end
end
