# frozen_string_literal: true

# ruby tools/release-audit/test/full_feature_canary_audit_test.rb
#
# E71-07 tdd (aggregation logic over fixture tool output; no capture, phone or Mac needed):
#   ci: fullFeatureCanaryAudit_manifestMissingKind_checkFails
#   ci: fullFeatureCanaryAudit_toolReportsFailOrNoJson_checkFails
#   ci: fullFeatureCanaryAudit_allChecksPass_exitsZeroReport

require 'minitest/autorun'
require_relative '../full-feature-canary-audit'

class FullFeatureCanaryAuditTest < Minitest::Test
  def full_manifest
    FullFeatureCanaryAudit::REQUIRED_KINDS.to_h { |k| [k, "TANDEM-CANARY-#{k}"] }
  end

  def test_parseManifest_commentsAndBlankLines_ignored
    manifest = FullFeatureCanaryAudit.parse_manifest("# c\n\nsmsBody=TANDEM-CANARY-a=b\n")
    assert_equal({ 'smsBody' => 'TANDEM-CANARY-a=b' }, manifest)
  end

  def test_parseManifest_lineWithoutCanary_raises
    assert_raises(RuntimeError) { FullFeatureCanaryAudit.parse_manifest("smsBody\n") }
  end

  def test_manifestCheck_missingKind_failsNamingKind
    manifest = full_manifest.reject { |k, _| k == 'mediaTicket' }
    check = FullFeatureCanaryAudit.manifest_check(manifest)
    refute check.pass?
    assert_includes check.detail, 'mediaTicket'
  end

  def test_manifestCheck_everyKind_passes
    assert FullFeatureCanaryAudit.manifest_check(full_manifest).pass?
  end

  def test_toolCheck_passJsonAndZeroExit_passes
    assert FullFeatureCanaryAudit.tool_check('x', %({"result": "pass", "occurrences": 0}\n), true).pass?
  end

  def test_toolCheck_failJson_fails
    refute FullFeatureCanaryAudit.tool_check('x', %({"result": "fail", "occurrences": 2}\n), false).pass?
  end

  def test_toolCheck_passJsonButNonZeroExit_fails
    refute FullFeatureCanaryAudit.tool_check('x', %({"result": "pass"}\n), false).pass?
  end

  def test_toolCheck_noJson_fails
    refute FullFeatureCanaryAudit.tool_check('x', "Traceback...\n", false).pass?
  end

  def test_toolCheck_brokenJson_fails
    refute FullFeatureCanaryAudit.tool_check('x', "{oops\n", true).pass?
  end

  def test_logCheck_failure_carriesOutput
    check = FullFeatureCanaryAudit.log_check('smsBody', 'logcat', "ERROR: canary found\n", false)
    refute check.pass?
    assert_includes check.detail, 'canary found'
  end

  def test_report_oneFailingCheck_exitsNonZeroAndNamesIt
    checks = [AuditReport.pass('a'), AuditReport.fail('b', 'boom')]
    refute AuditReport.ok?(checks)
    assert_includes AuditReport.render('t', checks), 'FAILED (b)'
  end

  def test_report_allPass_ok
    checks = [AuditReport.pass('a'), AuditReport.pass('b')]
    assert AuditReport.ok?(checks)
    assert_includes AuditReport.render('t', checks), '2 check(s) passed'
  end

  def test_report_noChecks_notOk
    refute AuditReport.ok?([])
  end
end
