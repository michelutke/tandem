#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/conformance/test/run_test.rb
#
# tdd (E15-03):
#   ci: conformanceRunSh_singleVectorFailure_exitsNonZeroNamingPlatformAndVector
#
# Stubs each platform's "run the conformance tests" command with a plain exit-code shell
# invocation plus a hand-written report fixture, rather than actually invoking Gradle/swift test
# (which E15-01/E15-02 already exercise and which would make this self-test slow and
# environment-dependent).

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'open3'
require_relative '../run'

class ConformanceRunnerTest < Minitest::Test
  RUN_RB = File.join(__dir__, '..', 'run.rb')

  def setup
    @tmp = Dir.mktmpdir('conformance-runner-test')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  # The stub "command" is a real script, not a pre-written file: like the real gradlew/swift test
  # invocation, writing the report is a side effect of running the command, so `run_one`'s
  # rm_f-before-run doesn't just delete a fixture out from under itself.
  def stub_platform(name, exit_code:, records: nil)
    report_file = File.join(@tmp, "#{name}-report.json")
    script = File.join(@tmp, "#{name}.sh")
    body = +"#!/bin/sh\n"
    body << "cat > '#{report_file}' <<'JSON'\n#{JSON.generate(records)}\nJSON\n" if records
    body << "exit #{exit_code}\n"
    File.write(script, body)
    File.chmod(0o755, script)
    {
      chdir: @tmp,
      command: [script],
      report_file: report_file
    }
  end

  def test_conformanceRunSh_singleVectorFailure_exitsNonZeroNamingPlatformAndVector
    android = stub_platform('android', exit_code: 0, records: [
                               { 'vectorId' => 'frame-min-size', 'category' => 'frame-encoding',
                                 'outcome' => 'pass', 'expected' => 'a', 'actual' => 'a' }
                             ])
    macos = stub_platform('macos', exit_code: 0, records: [
                             { 'vectorId' => 'spki-fixture-a', 'category' => 'spki-fingerprint',
                               'outcome' => 'fail', 'expected' => 'aa', 'actual' => 'bb' }
                           ])

    result = ConformanceRunner.run(platforms: { 'android' => android, 'macos' => macos }, report_dir: @tmp)

    assert_equal 'FAIL', result[:overall]
    assert_includes result[:failing], { platform: 'macos', vectorId: 'spki-fixture-a', category: 'spki-fingerprint' }
  end

  def test_conformanceRunner_allPass_overallPassAndReportWritten
    android = stub_platform('android', exit_code: 0, records: [
                               { 'vectorId' => 'a', 'category' => 'frame-encoding',
                                 'outcome' => 'pass', 'expected' => 'x', 'actual' => 'x' }
                             ])
    macos = stub_platform('macos', exit_code: 0, records: [
                             { 'vectorId' => 'b', 'category' => 'spki-fingerprint',
                               'outcome' => 'pass', 'expected' => 'y', 'actual' => 'y' }
                           ])

    result = ConformanceRunner.run(platforms: { 'android' => android, 'macos' => macos }, report_dir: @tmp)
    path = ConformanceRunner.write_report(@tmp, result)

    assert_equal 'PASS', result[:overall]
    assert File.exist?(path)
    data = JSON.parse(File.read(path))
    assert_equal 'PASS', data['overall']
    assert_equal 2, data['records'].size
  end

  def test_conformanceRunner_platformCommandFails_overallFailEvenWithoutReport
    android = stub_platform('android', exit_code: 1)
    macos = stub_platform('macos', exit_code: 0, records: [])

    result = ConformanceRunner.run(platforms: { 'android' => android, 'macos' => macos }, report_dir: @tmp)

    assert_equal 'FAIL', result[:overall]
    android_result = result[:platforms].find { |p| p[:platform] == 'android' }
    refute android_result[:commandOk]
  end

  def test_conformanceRunner_onlyOnePlatformGiven_reportsExactlyThatPlatform
    android = stub_platform('android', exit_code: 0, records: [
                               { 'vectorId' => 'a', 'category' => 'frame-encoding',
                                 'outcome' => 'pass', 'expected' => 'x', 'actual' => 'x' }
                             ])

    result = ConformanceRunner.run(platforms: { 'android' => android }, report_dir: @tmp)

    assert_equal 1, result[:platforms].size
    assert_equal 'android', result[:platforms].first[:platform]
    assert_equal 'PASS', result[:overall]
  end

  def test_conformanceRunSh_unknownOnlyFlag_exitsNonZero
    _out, _err, status = Open3.capture3('ruby', RUN_RB, '--only', 'nonexistent')

    refute status.success?
  end
end
