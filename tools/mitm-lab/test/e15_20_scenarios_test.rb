#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e15_20_scenarios_test.rb
#
# Structural checks for the E15-20 scenario directory (the scenarios themselves need the real Mac app
# and loopback aliases, so they run via runner.rb, not here).

require 'minitest/autorun'
require 'open3'
require_relative '../runner'

class MitmLabE1520ScenariosTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DIR = File.join(ROOT, 'e15-20-preauth-dos')
  SCENARIOS = File.join(DIR, 'scenarios')
  EXPECTED = %w[
    mitmLabDos_stalledTcpNoClientHello_closedWithin11s
    mitmLabDos_tlsDoneNoVersionHello_closedProtocolTimeoutWithin6s
    mitmLabDos_connectionFloodFromOneSource_pairedPeerStillReady
    mitmLabDos_failedHandshakeBurst_sourceThrottledOtherSourceReady
    mitmLabDos_threeIdlePairingCandidates_windowExhaustedNoPairAccepted
  ].freeze

  def test_mitmLabDos_scenarioDirectory_containsTheFiveTddScenarios
    assert_equal EXPECTED.sort, Dir.children(SCENARIOS).sort
  end

  def test_mitmLabDos_scenarios_haveValidExecutableHeaders
    EXPECTED.each do |name|
      path = File.join(SCENARIOS, name)
      assert File.executable?(path), "#{name} is not executable"
      meta = MitmLab.parse_metadata(path)
      assert_equal name, meta.name
      assert_equal 'client', meta.role
    end
  end

  def test_mitmLabDos_probe_buildsAndPassesVet
    skip 'go not installed' unless system('command -v go >/dev/null 2>&1')

    _out, err, status = Open3.capture3('go', 'vet', File.join(DIR, 'lib/preauth_probe.go'))
    assert status.success?, err
  end
end
