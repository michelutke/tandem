#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e20_20_scenarios_test.rb
#
# E20-20 tdd (structure only; the scenarios need the real Mac app):
#   ci: mitmLabE2020_scenarioFiles_parseAsExecutableClientScenariosExpectingLimitExceeded

require 'minitest/autorun'
require_relative '../runner'

class MitmLabE2020ScenariosTest < Minitest::Test
  DIR = File.expand_path('../e20-20-auth-flood/scenarios', __dir__)

  def scenario_paths
    Dir.children(DIR).sort.map { |f| File.join(DIR, f) }
  end

  def test_mitmLabE2020_scenarioFiles_parseAsExecutableClientScenariosExpectingLimitExceeded
    paths = scenario_paths
    assert_equal 2, paths.size
    paths.each do |path|
      assert File.executable?(path), "#{path} not executable"
      meta = MitmLab.parse_metadata(path)
      assert_equal 'client', meta.role
      assert_equal 'closedWithCode(LIMIT_EXCEEDED)', meta.expect
      assert_equal File.basename(path), meta.name
    end
  end

  def test_mitmLabE2020_scenarioFiles_sourceSharedLibAndAssertTrustUnchanged
    scenario_paths.each do |path|
      body = File.read(path)
      assert_includes body, 'e20-20-common.sh'
      assert_includes body, 'E20_20_TRUST_COUNT_AFTER'
    end
  end
end
