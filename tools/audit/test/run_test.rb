#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/audit/test/run_test.rb
#
# tdd (E15-18):
#   unit: auditRunner_oneStubToolFails_overallExitNonZeroNamingTool
#   unit: auditRunner_allStubsPass_jsonAndMarkdownReportsAgree
#   unit: auditRunner_onlyFlag_invokesExactlyOneTool
#   unit: auditReport_manualGateSteps_listedPendingNotPassed
#   unit: auditRunner_stepDiscovery_runsEveryAuditStepScript

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'open3'
require_relative '../run'

class AuditRunnerTest < Minitest::Test
  PASS_SCRIPT = "#!/bin/sh\nexit 0\n"
  FAIL_SCRIPT = "#!/bin/sh\necho 'boom: something broke'\nexit 1\n"
  MANUAL_GATE_SCRIPT = "#!/bin/sh\necho 'MANUAL-GATE: docs/testing/manual-gates.md#nmap'\nexit 0\n"
  LOGGING_PASS_SCRIPT = <<~SH
    #!/bin/sh
    echo "$@" >> "$(dirname "$0")/invoked.log"
    exit 0
  SH

  RUN_RB = File.join(__dir__, '..', 'run.rb')

  def setup
    @tmp = Dir.mktmpdir('audit-runner-test')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def write_tool(name, script_body, tools_root: @tmp)
    dir = File.join(tools_root, name)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, 'audit-step.sh')
    File.write(path, script_body)
    File.chmod(0o755, path)
    dir
  end

  def test_auditRunner_stepDiscovery_runsEveryAuditStepScript
    write_tool('alpha', PASS_SCRIPT)
    write_tool('beta', PASS_SCRIPT)
    write_tool('gamma', PASS_SCRIPT)
    FileUtils.mkdir_p(File.join(@tmp, 'not-a-tool')) # no audit-step.sh: must not be discovered

    discovered = AuditRunner.discover(@tmp)

    assert_equal %w[alpha beta gamma], discovered

    report = AuditRunner.run(tools_root: @tmp, subset: 'full')

    assert_equal %w[alpha beta gamma], report[:results].map { |r| r[:tool] }
    assert(report[:results].all? { |r| r[:status] == 'passed' })
  end

  def test_auditRunner_oneStubToolFails_overallExitNonZeroNamingTool
    write_tool('alpha', PASS_SCRIPT)
    write_tool('beta', FAIL_SCRIPT)

    report = AuditRunner.run(tools_root: @tmp, subset: 'ci')

    assert_equal 'FAIL', report[:overall]
    beta_result = report[:results].find { |r| r[:tool] == 'beta' }
    refute_nil beta_result
    assert_equal 'failed', beta_result[:status]
    assert_includes beta_result[:detail], 'boom'

    alpha_result = report[:results].find { |r| r[:tool] == 'alpha' }
    assert_equal 'passed', alpha_result[:status]
    assert_equal '', alpha_result[:detail]
  end

  def test_auditRunnerCli_failingStub_processExitCodeNonZero
    write_tool('alpha', PASS_SCRIPT)
    write_tool('beta', FAIL_SCRIPT)
    report_dir = File.join(@tmp, 'reports')
    FileUtils.mkdir_p(report_dir)

    _out, _err, status = Open3.capture3(
      'ruby', RUN_RB, '--tools-root', @tmp, '--report-dir', report_dir, '--subset', 'ci'
    )

    refute status.success?, 'expected non-zero process exit code on a failing stub'
    assert File.exist?(File.join(report_dir, 'report.json'))
  end

  def test_auditRunner_allStubsPass_jsonAndMarkdownReportsAgree
    write_tool('alpha', PASS_SCRIPT)
    write_tool('beta', PASS_SCRIPT)
    report_dir = File.join(@tmp, 'reports')
    FileUtils.mkdir_p(report_dir)

    report = AuditRunner.run(tools_root: @tmp, subset: 'full')
    json_path, md_path = AuditRunner.write_reports(
      report_dir, subset: report[:subset], overall: report[:overall], results: report[:results]
    )

    assert_equal 'PASS', report[:overall]
    assert File.exist?(json_path)
    assert File.exist?(md_path)

    json_data = JSON.parse(File.read(json_path))
    md_text = File.read(md_path)

    assert_equal 'PASS', json_data['overall']
    %w[alpha beta].each do |tool|
      step = json_data['steps'].find { |s| s['tool'] == tool }
      refute_nil step
      assert_equal 'passed', step['status']
      assert_includes md_text, tool
      assert_includes md_text, 'passed'
    end
  end

  def test_auditRunner_onlyFlag_invokesExactlyOneTool
    write_tool('alpha', LOGGING_PASS_SCRIPT)
    write_tool('beta', LOGGING_PASS_SCRIPT)
    write_tool('gamma', LOGGING_PASS_SCRIPT)

    report = AuditRunner.run(tools_root: @tmp, subset: 'full', only: 'beta')

    assert_equal 1, report[:results].size
    assert_equal 'beta', report[:results].first[:tool]

    refute File.exist?(File.join(@tmp, 'alpha', 'invoked.log'))
    refute File.exist?(File.join(@tmp, 'gamma', 'invoked.log'))
    beta_log = File.join(@tmp, 'beta', 'invoked.log')
    assert File.exist?(beta_log)
    assert_equal 1, File.readlines(beta_log).size
  end

  def test_auditRunner_onlyFlag_unknownTool_raisesArgumentError
    write_tool('alpha', PASS_SCRIPT)

    error = assert_raises(ArgumentError) do
      AuditRunner.run(tools_root: @tmp, subset: 'full', only: 'nonexistent')
    end
    assert_includes error.message, 'nonexistent'
  end

  def test_auditRunner_zeroToolsDiscovered_raisesArgumentError
    assert_raises(ArgumentError) do
      AuditRunner.run(tools_root: @tmp, subset: 'full')
    end
  end

  def test_auditReport_manualGateSteps_listedPendingNotPassed
    write_tool('alpha', PASS_SCRIPT)
    write_tool('nmap', MANUAL_GATE_SCRIPT)

    report = AuditRunner.run(tools_root: @tmp, subset: 'full')

    nmap_result = report[:results].find { |r| r[:tool] == 'nmap' }
    refute_nil nmap_result
    assert_equal 'pending', nmap_result[:status]
    assert_equal 'docs/testing/manual-gates.md#nmap', nmap_result[:detail]

    # A pending manual gate must not flip overall to FAIL.
    assert_equal 'PASS', report[:overall]

    report_dir = File.join(@tmp, 'reports')
    FileUtils.mkdir_p(report_dir)
    json_path, md_path = AuditRunner.write_reports(
      report_dir, subset: report[:subset], overall: report[:overall], results: report[:results]
    )
    json_data = JSON.parse(File.read(json_path))
    nmap_step = json_data['steps'].find { |s| s['tool'] == 'nmap' }
    assert_equal 'pending', nmap_step['status']
    refute_equal 'passed', nmap_step['status']
    assert_includes File.read(md_path), 'pending'
  end

  # tdd (E15-23)
  def test_auditGate_phase1FullRun_everyExpectedStepReported
    write_tool('alpha', PASS_SCRIPT)
    write_tool('beta', MANUAL_GATE_SCRIPT)
    expected = File.join(@tmp, 'expected-steps.txt')
    File.write(expected, "# comment\nalpha\n\nbeta\n")

    report = AuditRunner.run(tools_root: @tmp, subset: 'full', expected: AuditRunner.read_expected(expected))

    assert_equal 'PASS', report[:overall]
    assert_equal %w[alpha beta], report[:results].map { |r| r[:tool] }
    assert_equal %w[passed pending], report[:results].map { |r| r[:status] }
  end

  def test_auditGate_expectedStepMissing_runFailsNamingStep
    write_tool('alpha', PASS_SCRIPT)
    expected = File.join(@tmp, 'expected-steps.txt')
    File.write(expected, "alpha\nghost\n")
    report_dir = File.join(@tmp, 'reports')
    FileUtils.mkdir_p(report_dir)

    report = AuditRunner.run(tools_root: @tmp, subset: 'full', expected: AuditRunner.read_expected(expected))

    assert_equal 'FAIL', report[:overall]
    ghost = report[:results].find { |r| r[:tool] == 'ghost' }
    assert_equal 'failed', ghost[:status]
    assert_includes ghost[:detail], 'expected step not discovered'

    out, _err, status = Open3.capture3(
      'ruby', RUN_RB, '--tools-root', @tmp, '--report-dir', report_dir, '--subset', 'full', '--expected', expected
    )
    refute status.success?
    assert_includes out, 'ghost'
  end
end
