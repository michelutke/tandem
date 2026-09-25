# frozen_string_literal: true

# ruby tools/release-audit/test/android_manifest_check_test.rb
#
# E00-28 tdd (all pure text/XML fixtures; no Android SDK needed, unlike
# android_release_scan_test.sh, so this runs from repo-checks.yml's
# `tools/release-audit/test/*_test.rb` glob):
#   ci: mergedManifest_allowBackupTrueFixture_checkFails
#   ci: networkSecurityConfig_userTrustAnchorsOrCleartextFixture_checkFails
#   ci: exportedComponentCheck_unlistedExportedActivityFixture_checkFails
#   ci: deniedPermissionCheck_queryAllPackagesFixture_checkFails

require 'minitest/autorun'
require 'tmpdir'
require_relative '../check-android-manifest'

class AndroidManifestCheckTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/android-manifest', __dir__)

  def fixture(name)
    AndroidManifestCheck.read_xml(File.join(FIXTURES, name))
  end

  # --- backup / data extraction attributes ---

  def test_mergedManifest_allowBackupTrueFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-allow-backup-true.xml'))

    assert(violations.any? { |v| v.include?('allowBackup') })
  end

  def test_mergedManifest_missingDataExtractionRulesAttribute_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-missing-data-extraction-rules.xml'))

    assert(violations.any? { |v| v.include?('dataExtractionRules') })
  end

  def test_mergedManifest_validFixture_checkPasses
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-valid.xml'),
      allowlist: { 'dev.tandem.app.MainActivity' => nil },
    )

    assert_empty violations
  end

  def test_dataExtractionRules_missingExclusion_checkFails
    violations = AndroidManifestCheck.check_data_extraction_rules(fixture('data-extraction-rules-missing-exclusion.xml'))

    assert(violations.any? { |v| v.include?('cloud-backup') })
  end

  def test_dataExtractionRules_validFixture_checkPasses
    assert_empty AndroidManifestCheck.check_data_extraction_rules(fixture('data-extraction-rules-valid.xml'))
  end

  # --- network security config ---

  def test_networkSecurityConfig_userTrustAnchorsOrCleartextFixture_checkFails
    user_anchor_violations = AndroidManifestCheck.check_network_security_config(fixture('nsc-user-trust-anchor.xml'))
    assert(user_anchor_violations.any? { |v| v.include?('src="user"') })

    cleartext_violations = AndroidManifestCheck.check_network_security_config(fixture('nsc-cleartext-permitted.xml'))
    assert(cleartext_violations.any? { |v| v.include?('cleartextTrafficPermitted') })

    debug_override_violations = AndroidManifestCheck.check_network_security_config(fixture('nsc-debug-overrides.xml'))
    assert(debug_override_violations.any? { |v| v.include?('debug-overrides') })
  end

  def test_networkSecurityConfig_validFixture_checkPasses
    assert_empty AndroidManifestCheck.check_network_security_config(fixture('nsc-valid.xml'))
  end

  # --- exported components ---

  def test_exportedComponentCheck_unlistedExportedActivityFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-unlisted-exported-activity.xml'))

    assert(violations.any? { |v| v.include?('dev.tandem.app.RogueActivity') && v.include?('android-exported.allowlist') })
  end

  def test_exportedComponentCheck_allowlistedServiceMissingPermission_checkFailsNamingComponent
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-allowlisted-service-missing-permission.xml'),
      allowlist: { 'dev.tandem.app.TileService' => 'android.permission.BIND_QUICK_SETTINGS_TILE' },
    )

    assert(violations.any? { |v| v.include?('dev.tandem.app.TileService') && v.include?('BIND_QUICK_SETTINGS_TILE') })
  end

  def test_exportedComponentCheck_allowlistedActivityWithNoRequiredPermission_checkPasses
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-valid.xml'),
      allowlist: { 'dev.tandem.app.MainActivity' => nil },
    )

    assert_empty violations
  end

  # --- denied permissions ---

  def test_deniedPermissionCheck_queryAllPackagesFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-query-all-packages.xml'))

    assert(violations.any? { |v| v.include?('QUERY_ALL_PACKAGES') })
  end

  def test_deniedPermissionCheck_allowlistedException_checkPasses
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-query-all-packages.xml'),
      denied_permissions_allowlist: Set['android.permission.QUERY_ALL_PACKAGES'],
    )

    assert_empty violations
  end

  # --- allowlist / denylist loading ---

  def test_loadAllowlist_dashPermission_mapsToNil
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'allowlist')
      File.write(path, "# comment\ndev.tandem.app.MainActivity -\ndev.tandem.app.TileService android.permission.BIND_QUICK_SETTINGS_TILE\n")

      allowlist = AndroidManifestCheck.load_allowlist(path)

      assert_nil allowlist['dev.tandem.app.MainActivity']
      assert_equal 'android.permission.BIND_QUICK_SETTINGS_TILE', allowlist['dev.tandem.app.TileService']
    end
  end

  def test_loadAllowlist_missingFile_returnsEmpty
    assert_empty AndroidManifestCheck.load_allowlist('/nonexistent/allowlist')
  end
end
