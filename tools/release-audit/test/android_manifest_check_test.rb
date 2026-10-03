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
#   ci: dataExtractionRules_rootOnlyFixture_checkFails
#   ci: deniedPermissionCheck_usesPermissionSdk23QueryAllPackagesFixture_checkFails
#   ci: allowlist_malformedLine_loadRaises
#   ci: mergedManifest_missingNetworkSecurityConfigOrCleartextFixture_checkFails
#   ci: releaseManifest_declaredPermissions_matchAllowlist (E71-09)
#   ci: mergedManifest_notificationListener_requiresBindNotificationListenerPermission (E30-02)

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

  def test_mergedManifest_missingNetworkSecurityConfigFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-missing-network-security-config.xml'))

    assert(violations.any? { |v| v.include?('networkSecurityConfig') })
  end

  def test_mergedManifest_cleartextTrafficTrueFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-cleartext-traffic-true.xml'))

    assert(violations.any? { |v| v.include?('usesCleartextTraffic') })
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

  def test_dataExtractionRules_rootOnlyFixture_checkFails
    violations = AndroidManifestCheck.check_data_extraction_rules(fixture('data-extraction-rules-root-only.xml'))

    assert(violations.any? { |v| v.include?('cloud-backup') && v.include?('file') })
    assert(violations.any? { |v| v.include?('device-transfer') && v.include?('sharedpref') })
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

  # E30-02: the real NotificationListenerService declaration/allowlist entry, exercised by name
  # rather than relying on the generic TileService fixture above.
  def test_mergedManifest_notificationListener_requiresBindNotificationListenerPermission
    notification_listener_allowlist = {
      'dev.tandem.feature.notifications.TandemNotificationListenerService' =>
        'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE',
    }

    missing_permission_violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-notification-listener-missing-permission.xml'),
      allowlist: notification_listener_allowlist,
    )
    assert(
      missing_permission_violations.any? do |v|
        v.include?('TandemNotificationListenerService') && v.include?('BIND_NOTIFICATION_LISTENER_SERVICE')
      end,
    )

    assert_empty AndroidManifestCheck.check_manifest(
      fixture('manifest-notification-listener-valid.xml'),
      allowlist: notification_listener_allowlist,
    )
  end

  # --- denied permissions ---

  def test_deniedPermissionCheck_queryAllPackagesFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-query-all-packages.xml'))

    assert(violations.any? { |v| v.include?('QUERY_ALL_PACKAGES') })
  end

  def test_deniedPermissionCheck_usesPermissionSdk23QueryAllPackagesFixture_checkFails
    violations = AndroidManifestCheck.check_manifest(fixture('manifest-uses-permission-sdk-23-query-all-packages.xml'))

    assert(violations.any? { |v| v.include?('QUERY_ALL_PACKAGES') && v.include?('uses-permission-sdk-23') })
  end

  def test_deniedPermissionCheck_allowlistedException_checkPasses
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-query-all-packages.xml'),
      denied_permissions_allowlist: Set['android.permission.QUERY_ALL_PACKAGES'],
    )

    assert_empty violations
  end

  # --- allowlist / denylist loading ---

  # --- E71-09 declared permissions == allowlist ---

  PERMISSIONS_ALLOWLIST = Set['android.permission.POST_NOTIFICATIONS'].freeze

  def test_releaseManifest_declaredPermissions_matchAllowlist
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-permissions-valid.xml'),
      allowlist: { 'dev.tandem.app.MainActivity' => nil },
      permissions_allowlist: PERMISSIONS_ALLOWLIST,
    )

    assert_empty violations
  end

  def test_releaseManifest_unlistedPermissionFixture_checkFailsNamingPermission
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-permission-unlisted.xml'),
      allowlist: { 'dev.tandem.app.MainActivity' => nil },
      permissions_allowlist: PERMISSIONS_ALLOWLIST,
    )

    assert(violations.any? { |v| v.include?('android.permission.CAMERA') && v.include?('android-permissions.allowlist') })
  end

  def test_releaseManifest_allowlistedPermissionNotDeclared_checkFailsNamingPermission
    violations = AndroidManifestCheck.check_manifest(
      fixture('manifest-valid.xml'),
      allowlist: { 'dev.tandem.app.MainActivity' => nil },
      permissions_allowlist: PERMISSIONS_ALLOWLIST,
    )

    assert(violations.any? { |v| v.include?('android.permission.POST_NOTIFICATIONS') && v.include?('not declared') })
  end

  def test_loadPermissionsAllowlist_lineWithoutIssueId_raisesMalformed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'permissions.allowlist')
      File.write(path, "android.permission.POST_NOTIFICATIONS\n")

      assert_raises(AndroidManifestCheck::MalformedAllowlistError) { AndroidManifestCheck.load_permissions_allowlist(path) }
    end
  end

  def test_loadPermissionsAllowlist_checkedInFile_everyLineHasIssueId
    permissions = AndroidManifestCheck.load_permissions_allowlist(AndroidManifestCheck::DEFAULT_PERMISSIONS_ALLOWLIST)

    refute_empty permissions
  end

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

  def test_loadAllowlist_lineMissingPermissionColumn_raisesMalformed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'allowlist')
      File.write(path, "dev.tandem.app.TileService\n")

      error = assert_raises(AndroidManifestCheck::MalformedAllowlistError) { AndroidManifestCheck.load_allowlist(path) }
      assert_match(/expected exactly 2 whitespace-separated tokens/, error.message)
      assert_match(/:1:/, error.message)
    end
  end

  def test_loadAllowlist_lineWithTrailingComment_raisesMalformed
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'allowlist')
      File.write(path, "dev.tandem.app.TileService android.permission.BIND_QUICK_SETTINGS_TILE # why\n")

      assert_raises(AndroidManifestCheck::MalformedAllowlistError) { AndroidManifestCheck.load_allowlist(path) }
    end
  end
end
