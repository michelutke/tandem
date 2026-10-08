#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/log-audit/test/calls-pii_test.rb
#
# tdd (E52-09):
#   security: logAudit_jvmClientCallCanarySession_zeroCanaryMatches
#   security: logAudit_phoneCallCanarySession_zeroMatchesInLogcatAndMacLog
#
# The phone session is a manual gate (docs/testing/manual-gates.md, E52-08 call gates); here its audit contract
# is exercised on synthetic captures, and the call sources are scanned for any logging call so a
# captured session cannot contain caller names or numbers. The two mitmLab tdd entries (MMI address,
# burst of five requests) are covered by PlaceCallHandlerTest in android/feature/calls.

require 'minitest/autorun'
require 'open3'
require 'securerandom'
require 'tmpdir'

class CallsPiiTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  SCRIPT = File.join(ROOT, 'tools/log-audit/log-audit.sh')

  CALLS_SOURCES = [
    'android/feature/calls/src/main',
    'android/app/src/main/kotlin/dev/tandem/app/connection/feature/CallsFeature.kt',
    'macos/Packages/FeatureCalls/Sources/FeatureCalls'
  ].freeze

  LOGGING_CALL = /\b(?:Log\.[vdiwe]|Timber\.|println|System\.(?:out|err)|Logger\b|NSLog|os_log|debugPrint|print|dump)\s*\(|\bos\.Logger\b/.freeze

  def nonce = SecureRandom.hex(8)

  def canary_fields(canary)
    { name: "#{canary} Alice", number: "+41 79 #{canary}" }
  end

  def capture(dir, name, lines)
    path = File.join(dir, name)
    File.write(path, lines.join("\n") + "\n")
    path
  end

  def audit(canary, logcat, unified)
    out, err, status = Open3.capture3(SCRIPT, '--canary', canary, '--logcat', logcat, '--unified-log', unified)
    [out + err, status.exitstatus]
  end

  def redacted_session
    [
      '10-03 12:00:00.100  1  2 I CallDetector: call_event state=RINGING direction=CALL_DIRECTION_INCOMING',
      '10-03 12:00:00.200  1  2 I PlaceCallHandler: place_call path=direct',
      '10-03 12:00:00.300  1  2 D Transport: Frame sent, size=4096 bytes'
    ]
  end

  def test_logAudit_jvmClientCallCanarySession_zeroCanaryMatches
    canary = "TANDEM-CANARY-#{nonce}"
    Dir.mktmpdir do |dir|
      jvm = capture(dir, 'jvm.log', redacted_session)
      mac = capture(dir, 'unified.log', redacted_session)

      output, exitstatus = audit(canary, jvm, mac)

      assert_equal 0, exitstatus, output
    end
  end

  def test_logAudit_phoneCallCanarySession_zeroMatchesInLogcatAndMacLog
    canary = "TANDEM-CANARY-#{nonce}"
    Dir.mktmpdir do |dir|
      logcat = capture(dir, 'logcat.txt', redacted_session)
      mac = capture(dir, 'unified.log', redacted_session)

      output, exitstatus = audit(canary, logcat, mac)

      assert_equal 0, exitstatus, output
    end
  end

  %i[name number].each do |field|
    define_method("test_logAudit_canaryCall#{field.to_s.capitalize}InLogcat_exitsNonZero") do
      canary = "TANDEM-CANARY-#{nonce}"
      leaked = canary_fields(canary).fetch(field)
      Dir.mktmpdir do |dir|
        logcat = capture(dir, 'logcat.txt', redacted_session + ["10-03 12:00:01.000  1  2 D CallDetector: ringing #{leaked}"])
        mac = capture(dir, 'unified.log', redacted_session)

        output, exitstatus = audit(canary, logcat, mac)

        refute_equal 0, exitstatus, output
        assert_includes output, 'logcat'
      end
    end

    define_method("test_logAudit_canaryCall#{field.to_s.capitalize}InMacLog_exitsNonZero") do
      canary = "TANDEM-CANARY-#{nonce}"
      leaked = canary_fields(canary).fetch(field)
      Dir.mktmpdir do |dir|
        logcat = capture(dir, 'logcat.txt', redacted_session)
        mac = capture(dir, 'unified.log', redacted_session + ["2026-10-03 12:00:01.000 Tandem[1:2] incoming call from #{leaked}"])

        output, exitstatus = audit(canary, logcat, mac)

        refute_equal 0, exitstatus, output
        assert_includes output, 'unified'
      end
    end
  end

  def test_callSources_anyLoggingCall_noneFound
    files = CALLS_SOURCES.flat_map do |rel|
      path = File.join(ROOT, rel)
      File.directory?(path) ? Dir[File.join(path, '**/*.{kt,swift}')] : [path]
    end
    refute_empty files
    hits = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix("#{ROOT}/")}:#{index + 1}: #{line.strip}" if line.match?(LOGGING_CALL) && !line.strip.start_with?('*', '//')
      end
    end

    assert_empty hits, "call sources must not log (invariant 7):\n#{hits.join("\n")}"
  end
end
