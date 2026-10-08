#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e73_05_scenarios_test.rb
#
# Structural checks for the E73-05 scenario directory (the scenarios themselves need the real Mac app
# and JVM client, so they run via runner.rb, not here).

require 'minitest/autorun'
require 'open3'
require_relative '../runner'

class MitmLabE7305ScenariosTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DIR = File.join(ROOT, 'e73-05-manual-pairing')
  SCENARIOS = File.join(DIR, 'scenarios')
  EXPECTED = {
    'mitmLab_manualPairingBruteForce_fourthAttempt_rejected' => 'handshakeRejected',
    'mitmLab_manualPairing_commitPhaseSkipped_rejectedNoPin' => 'noPairAccepted',
    'mitmLab_manualPairing_fingerprintPrefixOnly_rejectedNoPin' => 'noPairAccepted',
    'mitmLab_manualPairing_messageInQrPairingSession_connectionClosed' => 'noPairAccepted',
    'mitmLab_manualPairing_pairRequestOnManualWindow_rejectedAttemptBurned' => 'handshakeRejected'
  }.freeze

  def test_mitmLabManualPairing_scenarioDirectory_containsTheFiveScenarios
    assert_equal EXPECTED.keys.sort, Dir.children(SCENARIOS).sort
  end

  def test_mitmLabManualPairing_scenarios_haveValidExecutableHeaders
    EXPECTED.each do |name, outcome|
      path = File.join(SCENARIOS, name)
      assert File.executable?(path), "#{name} is not executable"
      meta = MitmLab.parse_metadata(path)
      assert_equal name, meta.name
      assert_equal 'client', meta.role
      assert_equal outcome, meta.expect
    end
  end

  def test_mitmLabManualPairing_scenariosAndLibrary_passBashSyntaxCheck
    files = Dir.children(SCENARIOS).map { |n| File.join(SCENARIOS, n) } + [File.join(DIR, 'lib/e73-05-common.sh')]
    files.each do |file|
      _out, err, status = Open3.capture3('bash', '-n', file)
      assert status.success?, "#{file}: #{err}"
    end
  end
end
