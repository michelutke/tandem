#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/log-audit/test/contacts-pii_test.rb
#
# tdd (E51-08):
#   security: logAudit_jvmClientContactsCanarySession_zeroCanaryMatches
#   security: logAudit_physicalPhoneContactsCanarySession_zeroMatchesInLogcatAndMacLog
#
# The physical-phone session is a manual gate (docs/testing/manual-gates.md#e51-08); here its
# audit contract is exercised on synthetic captures, and the contacts sources are scanned for any
# logging call so a captured session cannot contain contact fields.

require 'minitest/autorun'
require 'open3'
require 'securerandom'
require 'tmpdir'

class ContactsPiiTest < Minitest::Test
  ROOT = File.expand_path('../../..', __dir__)
  SCRIPT = File.join(ROOT, 'tools/log-audit/log-audit.sh')

  CONTACTS_SOURCES = [
    'android/feature/contacts/src/main',
    'macos/Packages/FeatureMessaging/Sources/FeatureMessaging/ContactsSyncClient.swift',
    'macos/Packages/TandemStore/Sources/TandemStore/ContactsStore.swift',
    'macos/Packages/TandemStore/Sources/TandemStore/GrdbContactsStore.swift',
    'macos/Packages/TandemStore/Sources/TandemStore/InMemoryContactsStore.swift',
    'macos/Packages/TandemStore/Sources/TandemStore/ContactRecords.swift'
  ].freeze

  LOGGING_CALL = /\b(?:Log\.[vdiwe]|Timber\.|println|System\.(?:out|err)|Logger\b|NSLog|os_log|debugPrint|print|dump)\s*\(|\bos\.Logger\b/.freeze

  def nonce = SecureRandom.hex(8)

  def canary_fields(canary)
    { name: "#{canary} Alice", number: "+41 79 #{canary}", email: "#{canary}@example.com" }
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
      '10-03 12:00:00.100  1  2 I ContactsSync: sync started pages=1',
      '10-03 12:00:00.200  1  2 I ContactsSync: sent contacts count=500 tombstones=1',
      '10-03 12:00:00.300  1  2 D Transport: Frame sent, size=4096 bytes'
    ]
  end

  def test_logAudit_jvmClientContactsCanarySession_zeroCanaryMatches
    canary = "TANDEM-CANARY-#{nonce}"
    Dir.mktmpdir do |dir|
      jvm = capture(dir, 'jvm.log', redacted_session)
      mac = capture(dir, 'unified.log', redacted_session)

      output, exitstatus = audit(canary, jvm, mac)

      assert_equal 0, exitstatus, output
    end
  end

  def test_logAudit_physicalPhoneContactsCanarySession_zeroMatchesInLogcatAndMacLog
    canary = "TANDEM-CANARY-#{nonce}"
    Dir.mktmpdir do |dir|
      logcat = capture(dir, 'logcat.txt', redacted_session)
      mac = capture(dir, 'unified.log', redacted_session)

      output, exitstatus = audit(canary, logcat, mac)

      assert_equal 0, exitstatus, output
    end
  end

  %i[name number email].each do |field|
    define_method("test_logAudit_canaryContact#{field.to_s.capitalize}InLogcat_exitsNonZero") do
      canary = "TANDEM-CANARY-#{nonce}"
      leaked = canary_fields(canary).fetch(field)
      Dir.mktmpdir do |dir|
        logcat = capture(dir, 'logcat.txt', redacted_session + ["10-03 12:00:01.000  1  2 D ContactsSync: upsert #{leaked}"])
        mac = capture(dir, 'unified.log', redacted_session)

        output, exitstatus = audit(canary, logcat, mac)

        refute_equal 0, exitstatus, output
        assert_includes output, 'logcat'
      end
    end

    define_method("test_logAudit_canaryContact#{field.to_s.capitalize}InMacLog_exitsNonZero") do
      canary = "TANDEM-CANARY-#{nonce}"
      leaked = canary_fields(canary).fetch(field)
      Dir.mktmpdir do |dir|
        logcat = capture(dir, 'logcat.txt', redacted_session)
        mac = capture(dir, 'unified.log', redacted_session + ["2026-10-03 12:00:01.000 Tandem[1:2] cache insert #{leaked}"])

        output, exitstatus = audit(canary, logcat, mac)

        refute_equal 0, exitstatus, output
        assert_includes output, 'unified'
      end
    end
  end

  def test_contactsSources_anyLoggingCall_noneFound
    files = CONTACTS_SOURCES.flat_map do |rel|
      path = File.join(ROOT, rel)
      File.directory?(path) ? Dir[File.join(path, '**/*.{kt,swift}')] : [path]
    end
    refute_empty files
    hits = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix("#{ROOT}/")}:#{index + 1}: #{line.strip}" if line.match?(LOGGING_CALL) && !line.strip.start_with?('*', '//')
      end
    end

    assert_empty hits, "contacts sources must not log (invariant 7):\n#{hits.join("\n")}"
  end
end
