# frozen_string_literal: true

# ruby tools/release-audit/test/network_audit_test.rb
#
# E71-08 tdd (aggregation logic over fixtures; no nmap, phone, Mac or openssl run):
#   ci: networkAudit_everyMitmLabDirectory_discovered
#   ci: networkAudit_unexpectedScenarioOutcome_checkFails
#   ci: networkAudit_tls12Negotiated_checkFails

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../network-audit'

class NetworkAuditTest < Minitest::Test
  def result(name, status, observed = 'x')
    MitmLab::Result.new(name: name, role: 'client', expected: 'x', observed: observed, status: status,
                        duration_s: 0.0, detail: '')
  end

  def test_scenarioDirs_realLab_coversEveryExpectedDirectory
    dirs = NetworkAudit.scenario_dirs
    assert NetworkAudit.missing_dirs_check(dirs).pass?
    refute(dirs.any? { |d| d.include?('selftest') })
  end

  def test_scenarioDirs_fixtureRoot_skipsDirsWithoutScenarios
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'e1-a/scenarios'))
      FileUtils.mkdir_p(File.join(root, 'test'))
      assert_equal [File.join(root, 'e1-a/scenarios')], NetworkAudit.scenario_dirs(root)
    end
  end

  def test_missingDirsCheck_absentDirectory_failsNamingIt
    dirs = NetworkAudit::EXPECTED_DIRS.reject { |d| d == 'e70-09-rotation' }.map { |d| "/lab/#{d}/scenarios" }
    check = NetworkAudit.missing_dirs_check(dirs)
    refute check.pass?
    assert_includes check.detail, 'e70-09-rotation'
  end

  def test_mitmCheck_allScenariosPass_passes
    report = MitmLab::Report.new(results: [result('a', :pass)], errors: [])
    assert NetworkAudit.mitm_check('/lab/e15-09-pairing-abuse/scenarios', report).pass?
  end

  def test_mitmCheck_unexpectedAcceptance_failsNamingScenario
    report = MitmLab::Report.new(results: [result('a', :pass), result('bad', :fail, 'pairAccepted')], errors: [])
    check = NetworkAudit.mitm_check('/lab/e15-09-pairing-abuse/scenarios', report)
    refute check.pass?
    assert_includes check.detail, 'bad (pairAccepted)'
  end

  def test_mitmCheck_runnerError_fails
    report = MitmLab::Report.new(results: [], errors: ['no scenario files found'])
    refute NetworkAudit.mitm_check('/lab/e20-20-auth-flood/scenarios', report).pass?
  end

  def test_nmapCheck_nonZeroExit_failsWithOutput
    check = NetworkAudit.nmap_check("ERROR: port 22 open\n", false)
    refute check.pass?
    assert_includes check.detail, 'port 22'
  end

  def test_nmapCheck_zeroExit_passes
    assert NetworkAudit.nmap_check('', true).pass?
  end

  def test_tls12Check_handshakeFailureOutput_passes
    assert NetworkAudit.tls12_check("error:0A00042E:SSL routines::tlsv1 alert protocol version\nCipher is (NONE)\n").pass?
  end

  def test_tls12Check_tls12Negotiated_fails
    refute NetworkAudit.tls12_check("    Protocol  : TLSv1.2\n    Cipher    : ECDHE\n").pass?
  end
end
