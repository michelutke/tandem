# frozen_string_literal: true

# E71-12 tdd:
#   ci: releaseAuditChecklist_rowWithoutEvidenceLink_exitsNonZero
#   ci: releaseAuditLinkCheck_allEvidenceLinks_resolve

require 'minitest/autorun'
require_relative '../check_release_audit_checklist'

class CheckReleaseAuditChecklistTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/release-audit', __dir__)

  def test_releaseAuditChecklist_rowWithoutEvidenceLink_exitsNonZero
    errors = ReleaseAuditChecklist.check_links(File.join(FIXTURES, 'no-link-row.md'))

    assert_equal 1, errors.size
    assert_includes errors.first, 'AC-01 has no link'
  end

  def test_releaseAuditLinkCheck_brokenLink_reported
    errors = ReleaseAuditChecklist.check_links(File.join(FIXTURES, 'broken-link-row.md'))

    assert(errors.any? { |e| e.include?('does-not-exist.md') })
  end

  def test_releaseAuditChecklist_decisionWithoutRow_reported
    errors = ReleaseAuditChecklist.check_coverage(File.join(FIXTURES, 'no-link-row.md'),
                                                  File.join(FIXTURES, 'decisions.md'))

    assert(errors.any? { |e| e.include?('D-01') })
    assert(errors.any? { |e| e.include?('AC-20') })
  end

  def test_releaseAuditLinkCheck_allEvidenceLinks_resolve
    assert_empty ReleaseAuditChecklist.check
  end
end
