#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/reconnect-harness/test/reconnect_harness_test.rb
#
# tdd (E20-12):
#   unit: reconnectHarness_fixtureLogs_computesP95AndExitsNonZeroAbove5s

require 'minitest/autorun'
require 'open3'
require_relative '../reconnect_harness'

class ReconnectHarnessTest < Minitest::Test
  FIXTURES = File.join(__dir__, '..', 'fixtures')
  RUN_RB = File.join(__dir__, '..', 'run.rb')

  def fixture(name) = File.join(FIXTURES, name)

  def latencies(name) = ReconnectHarness.latencies(File.read(fixture(name)))

  def test_latencies_logcat_firstReadyAfterEachEpisodeOpen
    assert_equal [2.0, 1.5, 3.0, 4.0], latencies('logcat-pass.log')
  end

  def test_latencies_macosUnifiedLog_parsed
    assert_equal [2.5], latencies('macos-unified.log')
  end

  def test_latencies_unrecoveredEpisode_reportedAsInfinity
    assert_equal [Float::INFINITY], latencies('logcat-unrecovered.log').last(1)
  end

  def test_percentile_nearestRank
    values = (1..20).map(&:to_f)
    assert_equal 19.0, ReconnectHarness.percentile(values, 95)
    assert_equal 4.0, ReconnectHarness.percentile([1.0, 2.0, 3.0, 4.0], 95)
  end

  def run_cli(*args) = Open3.capture3('ruby', RUN_RB, *args)

  def test_cli_p95Under5s_exitsZeroAndPrintsP95
    out, _err, status = run_cli(fixture('logcat-pass.log'))
    assert status.success?
    assert_includes out, 'trials=4'
    assert_includes out, 'p95=4.000s'
  end

  def test_cli_p95Above5s_exitsNonZero
    out, _err, status = run_cli(fixture('logcat-fail.log'))
    refute status.success?
    assert_includes out, 'p95=7.500s'
    assert_includes out, 'FAIL'
  end

  def test_cli_unrecoveredEpisode_exitsNonZero
    _out, _err, status = run_cli(fixture('logcat-unrecovered.log'))
    refute status.success?
  end

  def test_cli_minTrialsNotMet_exitsNonZero
    _out, _err, status = run_cli('--min-trials', '20', fixture('logcat-pass.log'))
    refute status.success?
  end

  def test_cli_noEpisodes_exitsNonZero
    _out, _err, status = run_cli(fixture('macos-unified.log').sub('macos-unified', 'missing'))
    refute status.success?
  end
end
