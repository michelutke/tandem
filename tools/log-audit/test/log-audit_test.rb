#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/log-audit/test/log-audit_test.rb
#
# tdd (E15-17):
#   unit: logAudit_canaryInLogcatFixture_exitsOneWithSourceAndLine
#   unit: logAudit_canaryInUnifiedLogFixture_exitsOneWithSourceAndLine
#   unit: logAudit_redactedLengthOnlyFixture_exitsZero
#   unit: logAudit_emptyLogCapture_exitsNonZero
#   unit: logAudit_base64urlEncodedCanary_detected
#   unit: logAudit_manifestMissingRequiredKindForEnabledFeature_exitsNonZero

require 'minitest/autorun'
require 'open3'
require 'base64'
require 'tmpdir'

class LogAuditTest < Minitest::Test
  SCRIPT = File.expand_path('../log-audit.sh', __dir__)
  FIXTURES = File.expand_path('fixtures', __dir__)

  def run_script(canary, logcat: nil, unified_log: nil)
    cmd = [SCRIPT, '--canary', canary]
    cmd.concat(['--logcat', logcat]) if logcat
    cmd.concat(['--unified-log', unified_log]) if unified_log

    stdout, stderr, status = Open3.capture3(*cmd)
    [stdout, stderr, status.exitstatus]
  end

  def test_logAudit_canaryInLogcatFixture_exitsOneWithSourceAndLine
    logcat = File.join(FIXTURES, 'logcat-with-canary.txt')
    canary = 'TANDEM-CANARY-abc123def456ghi789'

    stdout, stderr, exitstatus = run_script(canary, logcat: logcat)

    refute_equal 0, exitstatus, 'expected non-zero exit when canary is found'
    output = stdout + stderr
    assert_includes output, 'logcat', 'expected logcat source in output'
    assert_includes output, 'line', 'expected line number in output'
  end

  def test_logAudit_canaryInUnifiedLogFixture_exitsOneWithSourceAndLine
    unified = File.join(FIXTURES, 'unified-with-canary.txt')
    canary = 'TANDEM-CANARY-xyz789abc456def123'

    stdout, stderr, exitstatus = run_script(canary, unified_log: unified)

    refute_equal 0, exitstatus, 'expected non-zero exit when canary is found'
    output = stdout + stderr
    assert_includes output, 'unified', 'expected unified source in output'
    assert_includes output, 'line', 'expected line number in output'
  end

  def test_logAudit_redactedLengthOnlyFixture_exitsZero
    logcat = File.join(FIXTURES, 'logcat-redacted-only.txt')
    canary = 'TANDEM-CANARY-notpresent'

    stdout, stderr, exitstatus = run_script(canary, logcat: logcat)

    assert_equal 0, exitstatus, "expected zero exit on redacted-only logs, stderr: #{stderr}"
  end

  def test_logAudit_emptyLogCapture_exitsNonZero
    Dir.mktmpdir do |tmpdir|
      empty_log = File.join(tmpdir, 'empty.txt')
      File.write(empty_log, '')
      canary = 'TANDEM-CANARY-test'

      stdout, stderr, exitstatus = run_script(canary, logcat: empty_log)

      # Empty log = capture failed, so we should exit non-zero
      refute_equal 0, exitstatus, 'expected non-zero exit on empty log capture'
    end
  end

  def test_logAudit_base64urlEncodedCanary_detected
    logcat = File.join(FIXTURES, 'logcat-base64url-canary.txt')
    canary = 'TANDEM-CANARY-test123'

    stdout, stderr, exitstatus = run_script(canary, logcat: logcat)

    # The fixture contains base64 encoding of the canary, so it should be found
    refute_equal 0, exitstatus, 'expected non-zero exit when base64-encoded canary is in log'
    output = stdout + stderr
    assert_includes output, 'base64', 'expected base64 encoding noted'
  end

  def run_manifest(manifest_text, logcat: nil, unified_log: nil)
    Dir.mktmpdir do |tmpdir|
      manifest = File.join(tmpdir, 'canaries.txt')
      File.write(manifest, manifest_text)
      cmd = [SCRIPT, '--manifest', manifest]
      cmd.concat(['--logcat', logcat]) if logcat
      cmd.concat(['--unified-log', unified_log]) if unified_log
      stdout, stderr, status = Open3.capture3(*cmd)
      [stdout + stderr, status.exitstatus]
    end
  end

  def full_manifest_text(except: nil)
    kinds = File.readlines(File.join(__dir__, '..', 'required-canary-kinds.txt'), chomp: true)
    (kinds - [except]).map { |k| "#{k}=TANDEM-CANARY-absent-#{k}" }.join("\n") + "\n"
  end

  def test_logAudit_manifestMissingRequiredKindForEnabledFeature_exitsNonZero
    output, exitstatus = run_manifest(full_manifest_text(except: 'mediaTicket'),
                                      logcat: File.join(FIXTURES, 'logcat-redacted-only.txt'))

    refute_equal 0, exitstatus
    assert_includes output, 'mediaTicket'
  end

  def test_logAudit_manifestEveryKindAbsentFromLogs_exitsZero
    output, exitstatus = run_manifest(full_manifest_text,
                                      logcat: File.join(FIXTURES, 'logcat-redacted-only.txt'))

    assert_equal 0, exitstatus, output
  end

  def test_logAudit_manifestCanaryInLog_exitsOneWithSourceAndLine
    manifest = full_manifest_text(except: 'smsBody') + "smsBody=TANDEM-CANARY-abc123def456ghi789\n"
    output, exitstatus = run_manifest(manifest, logcat: File.join(FIXTURES, 'logcat-with-canary.txt'))

    refute_equal 0, exitstatus
    assert_includes output, 'logcat'
    assert_includes output, 'line'
  end

  def test_logAudit_manifestMalformedLine_exitsNonZero
    output, exitstatus = run_manifest("smsBody\n", logcat: File.join(FIXTURES, 'logcat-redacted-only.txt'))

    refute_equal 0, exitstatus
    assert_includes output, 'malformed'
  end
end
