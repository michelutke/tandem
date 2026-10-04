#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e70_09_scenarios_test.rb
#
# E70-09 tdd (structure only; the scenarios need the real Mac app):
#   ci: mitmLabE7009_scenarioFiles_parseAsExecutableClientScenariosAssertingTrustUnchanged

require 'minitest/autorun'
require_relative '../runner'

class MitmLabE7009ScenariosTest < Minitest::Test
  DIR = File.expand_path('../e70-09-rotation/scenarios', __dir__)
  EXPECTED = {
    'mitmLabRotation_keyRotationBeforeHelloComplete_rejectedTrustStoreUnchanged' => 'closedWithCode(PROTOCOL_TIMEOUT)',
    'mitmLabRotation_keyRotationInPairingWindow_rejectedTrustStoreUnchanged' => 'closedWithCode(PAIRING_FAILED)',
    'mitmLabRotation_unpinnedPeerSendsKeyRotation_handshakeFailsNoPinAdded' => 'handshakeRejected',
    'mitmLabRotation_keyRotationReplayedOnNewSession_rejectedTrustStoreUnchanged' => 'closedWithCode(INVALID_SIGNATURE)',
    'mitmLabRotation_newSpkiOfOtherPairedPeer_rejectedDuplicateKey' => 'closedWithCode(DUPLICATE_KEY)',
    'mitmLabRotation_pendingMacKeyOfferedBeforeAllAcks_unackedPhoneKeepsOldPinOnly' => 'handshakeRejected'
  }.freeze

  def scenario_paths
    Dir.children(DIR).sort.map { |f| File.join(DIR, f) }
  end

  def test_mitmLabE7009_scenarioFiles_parseAsExecutableClientScenariosAssertingTrustUnchanged
    paths = scenario_paths
    assert_equal EXPECTED.keys.sort, paths.map { |p| File.basename(p) }
    paths.each do |path|
      assert File.executable?(path), "#{path} not executable"
      meta = MitmLab.parse_metadata(path)
      assert_equal 'client', meta.role
      assert_equal File.basename(path), meta.name
      assert_equal EXPECTED.fetch(meta.name), meta.expect
    end
  end

  def test_mitmLabE7009_pendingMacKeyScenario_startsMacRotationAndNeverAcks
    body = File.read(File.join(DIR, 'mitmLabRotation_pendingMacKeyOfferedBeforeAllAcks_unackedPhoneKeepsOldPinOnly'))
    assert_includes body, '-HarnessMacRotation YES'
    assert_includes body, 'RAWMACROTATION NOACK'
    assert_includes body, 'harness-mac-rotation-switched'
  end

  def test_mitmLabE7009_scenarioFiles_sourceSharedLibAndCompareTrustSnapshots
    scenario_paths.each do |path|
      body = File.read(path)
      assert_includes body, 'e70-09-common.sh'
      assert_includes body, 'e70_09_assert_trust_unchanged "$TRUST_BEFORE"'
    end
  end
end
