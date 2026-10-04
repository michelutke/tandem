#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/e60_05_scenarios_test.rb
#
# E60-05 tdd (structure only; the scenarios need the real Mac app):
#   ci: mitmLabE6005_scenarioFiles_parseAsExecutableClientScenariosAssertingMediaRejection

require 'minitest/autorun'
require_relative '../runner'

class MitmLabE6005ScenariosTest < Minitest::Test
  DIR = File.expand_path('../e60-05-media-ticket/scenarios', __dir__)
  REJECTED = 'closedWithCode(TICKET_REJECTED)'
  EXPECTED = {
    'mitmLabMedia_mediaHelloWithoutTicket_rejectedAfterHandshake' => REJECTED,
    'mitmLabMedia_mediaReusedTicket_rejectedAfterHandshake' => REJECTED,
    'mitmLabMedia_mediaTicketAfter31s_rejectedAfterHandshake' => REJECTED,
    'mitmLabMedia_mediaTicketFromEndedSession_rejectedAfterHandshake' => REJECTED,
    'mitmLabMedia_mediaTicketOnOtherPeersClientCert_rejectedAfterHandshake' => REJECTED,
    'mitmLabMedia_mediaConnectionNoHelloFor6s_closedProtocolTimeout' => 'closedWithCode(PROTOCOL_TIMEOUT)'
  }.freeze
  REASONS = {
    'mitmLabMedia_mediaHelloWithoutTicket_rejectedAfterHandshake' => 'missing',
    'mitmLabMedia_mediaReusedTicket_rejectedAfterHandshake' => 'consumed',
    'mitmLabMedia_mediaTicketAfter31s_rejectedAfterHandshake' => 'expired',
    'mitmLabMedia_mediaTicketFromEndedSession_rejectedAfterHandshake' => 'revoked',
    'mitmLabMedia_mediaTicketOnOtherPeersClientCert_rejectedAfterHandshake' => 'peerMismatch'
  }.freeze

  def scenario_paths
    Dir.children(DIR).sort.map { |f| File.join(DIR, f) }
  end

  def test_mitmLabE6005_scenarioFiles_parseAsExecutableClientScenariosAssertingMediaRejection
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

  def test_mitmLabE6005_rejectionScenarios_sourceSharedLibAndAssertTheirReasonAndNoBind
    REASONS.each do |name, reason|
      body = File.read(File.join(DIR, name))
      assert_includes body, 'e60-05-common.sh'
      assert_includes body, "e60_05_assert_rejected #{reason}"
      assert_includes body, 'e60_05_assert_bound_count'
    end
  end
end
