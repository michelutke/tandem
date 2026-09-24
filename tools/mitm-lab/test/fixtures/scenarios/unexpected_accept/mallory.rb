#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixture scenario for mitmLabRunner_unexpectedAcceptance_exitsNonZeroNamingScenario. Connects to
# the test's local stub peer (MITM_TARGET_HOST/PORT); the stub peer answers instead of rejecting,
# so this deliberately observes "accepted" even though it declares "handshakeRejected" -- proving
# the runner treats an unexpected acceptance as a failure and names this scenario.
# mitm-scenario-name: mallory
# mitm-scenario-role: client
# mitm-scenario-expect: handshakeRejected
# mitm-scenario-timeout: 5
require 'socket'

host = ENV.fetch('MITM_TARGET_HOST')
port = Integer(ENV.fetch('MITM_TARGET_PORT'))

outcome =
  begin
    sock = TCPSocket.new(host, port)
    data = sock.gets
    sock.close
    data ? 'accepted' : 'handshakeRejected'
  rescue StandardError
    'handshakeRejected'
  end

puts "OUTCOME: #{outcome}"
