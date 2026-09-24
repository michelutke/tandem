#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/mitm-lab/test/runner_test.rb
#
# E15-08 tdd:
#   unit: mitmLabRunner_fixtureDirWithThreeScenarios_reportsThreeResults
#   unit: mitmLabRunner_unexpectedAcceptance_exitsNonZeroNamingScenario
#   unit: mitmLabRunner_scenarioExceedsTimeout_reportedAsFailed
#   unit: mitmLabRunner_emptyScenarioDirectory_exitsNonZero

require 'minitest/autorun'
require 'open3'
require 'socket'
require 'tmpdir'
require_relative '../runner'

class MitmLabRunnerTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  RUNNER = File.join(ROOT, 'runner.rb')
  FIXTURES = File.join(ROOT, 'test/fixtures/scenarios')

  def run_cli(*args)
    Open3.capture3('ruby', RUNNER, *args)
  end

  def test_mitmLabRunner_fixtureDirWithThreeScenarios_reportsThreeResults
    report = MitmLab.run(dir: File.join(FIXTURES, 'three_pass'))

    assert_equal 3, report.results.size
    assert report.ok?, report.results.reject(&:pass?).map(&:detail).inspect
  end

  def test_mitmLabRunner_unexpectedAcceptance_exitsNonZeroNamingScenario
    with_accepting_stub_peer do |port|
      stdout, stderr, status = run_cli(File.join(FIXTURES, 'unexpected_accept'), '--target-host', '127.0.0.1',
                                        '--target-port', port.to_s)

      refute status.success?
      assert_includes stdout + stderr, 'mallory'
      assert_includes stdout, 'observed=accepted'
    end
  end

  def test_mitmLabRunner_scenarioExceedsTimeout_reportedAsFailed
    report = MitmLab.run(dir: File.join(FIXTURES, 'timeout'))

    assert_equal 1, report.results.size
    result = report.results.first
    refute result.pass?
    assert_equal 'timeout', result.observed
    assert_operator result.duration_s, :<, 3.0
  end

  def test_mitmLabRunner_emptyScenarioDirectory_exitsNonZero
    Dir.mktmpdir do |dir|
      report = MitmLab.run(dir: dir)
      refute report.ok?
      assert_equal 1, report.errors.size

      _stdout, _stderr, status = run_cli(dir)
      refute status.success?
    end
  end

  private

  # A minimal local stub peer that accepts a connection and answers instead of rejecting it, so
  # the "unexpected acceptance" fixture (mallory.rb) has something real to connect to.
  def with_accepting_stub_peer
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    thread = Thread.new do
      loop do
        client = server.accept
        client.puts('hello from stub peer')
        client.close
      end
    rescue IOError
      nil
    end

    yield port
  ensure
    thread&.kill
    server&.close
  end
end
