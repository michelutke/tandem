#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/lint/test/release_log_check_test.rb
#
# tdd (E00-27):
#   ci: releaseLogLint_notificationBodyViaOsLog_checkFails
#   ci: releaseLogLint_notificationBodyInsideIfDebug_checkPasses
#   ci: releaseLogLint_redactedLengthOnlyLog_checkPasses
#   ci: releaseLogLint_publicPrivacyOnStringValue_checkFails

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../release-log-check'

class ReleaseLogCheckTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/swift', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  def test_releaseLogLint_notificationBodyViaOsLog_checkFails
    errors = ReleaseLogCheck.check(fixture('ReleaseLogSensitiveOsLogFixture.swift'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('notificationText') },
           "expected a notificationText error, got: #{errors.inspect}")
  end

  def test_releaseLogLint_notificationBodyInsideIfDebug_checkPasses
    errors = ReleaseLogCheck.check(fixture('ReleaseLogSensitiveInsideIfDebugFixture.swift'))

    assert_empty errors
  end

  def test_releaseLogLint_directoryNamedDotSwift_skippedNotRead
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, 'GRDB.swift'))

      assert_empty ReleaseLogCheck.check(dir)
    end
  end

  def test_releaseLogLint_buildOutputCheckouts_notScanned
    Dir.mktmpdir do |dir|
      vendored = File.join(dir, 'build', 'release', 'SourcePackages', 'checkouts', 'Dep')
      FileUtils.mkdir_p(vendored)
      FileUtils.cp(fixture('ReleaseLogSensitiveOsLogFixture.swift'), vendored)

      assert_empty ReleaseLogCheck.check(dir)
    end
  end

  def test_releaseLogLint_redactedLengthOnlyLog_checkPasses
    errors = ReleaseLogCheck.check(fixture('ReleaseLogRedactedLengthOnlyFixture.swift'))

    assert_empty errors
  end

  def test_releaseLogLint_publicPrivacyOnStringValue_checkFails
    errors = ReleaseLogCheck.check(fixture('ReleaseLogPublicPrivacyStringFixture.swift'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('privacy') },
           "expected a privacy error, got: #{errors.inspect}")
  end

  def test_releaseLogLint_publicPrivacyAllowlistedEnum_checkPasses
    errors = ReleaseLogCheck.check(fixture('ReleaseLogPublicPrivacyAllowlistedFixture.swift'))

    assert_empty errors
  end

  def test_releaseLogLint_nestedIfDebugElse_checkHandlesNestingCorrectly
    errors = ReleaseLogCheck.check(fixture('ReleaseLogNestedIfDebugFixture.swift'))

    assert_equal 1, errors.size
    assert_match(/:8:/, errors.first)
  end

  def test_releaseLogLint_ifNotDebug_checkFails
    errors = ReleaseLogCheck.check(fixture('ReleaseLogIfNotDebugFixture.swift'))

    refute_empty errors
  end

  def test_releaseLogLint_realMacosSources_checkPasses
    errors = ReleaseLogCheck.check(File.join(REPO_ROOT, 'macos'))

    assert_empty errors
  end
end
