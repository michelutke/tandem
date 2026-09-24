#!/usr/bin/env ruby
# frozen_string_literal: true

# Fixture scenario for mitmLabRunner_scenarioExceedsTimeout_reportedAsFailed: declares a 1s
# timeout but sleeps far longer, so the runner must kill it and report a failure, never a pass,
# even though its (never-reached) OUTCOME line would have matched its own expectation.
# mitm-scenario-role: client
# mitm-scenario-expect: handshakeRejected
# mitm-scenario-timeout: 1
sleep 5
puts 'OUTCOME: handshakeRejected'
