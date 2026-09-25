# frozen_string_literal: true

# ruby tools/release-audit/test/scan_test_code_test.rb
#
# Unit coverage for the pure denylist/text/bundle logic in scan-test-code.rb. The dexdump/nm-
# backed fixture acceptance tests (releaseApkDexScan_testOnlyClassFixture_exitsNonZero etc.) live
# in android_release_scan_test.sh and macos_release_scan_test.sh, which need a real SDK/Xcode
# toolchain and so are wired into android.yml / macos.yml rather than run here.

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../scan-test-code'

class ScanTestCodeTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir('release-audit')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def write(relative, bytes)
    path = File.join(@tmp, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    path
  end

  MACHO_MAGIC = [0xcffaedfe].pack('N').freeze

  # --- denylist loading ---

  def test_loadDenylist_blankAndCommentLines_ignored
    path = write('denylist.txt', <<~TXT)
      # comment
      SoftwareIdentityKeyStore

      TestClock
    TXT

    assert_equal %w[SoftwareIdentityKeyStore TestClock], ReleaseAudit.load_denylist(path)
  end

  # --- pattern matching ---

  def test_patternsFor_symbolWithDot_alsoReturnsSlashForm
    assert_equal %w[dev.tandem.companion dev/tandem/companion], ReleaseAudit.patterns_for('dev.tandem.companion')
  end

  def test_patternsFor_symbolWithoutDot_returnsOnlyItself
    assert_equal %w[TestClock], ReleaseAudit.patterns_for('TestClock')
  end

  def test_textMatches_dexSlashSeparatedDescriptor_matchesDottedDenylistEntry
    text = 'Ldev/tandem/companion/NotificationRelay;'
    assert_equal %w[dev.tandem.companion], ReleaseAudit.text_matches(text, ['dev.tandem.companion'])
  end

  def test_textMatches_symbolAbsent_returnsEmpty
    assert_empty ReleaseAudit.text_matches('nothing interesting here', %w[SoftwareIdentityKeyStore])
  end

  # --- file scanning ---

  def test_scanFiles_denylistedClassInDump_reportsSymbolAndPath
    dump = write('dump.txt', "0001: new-instance v0, Ldev/tandem/core/testing/TestClock;\n")

    matches = ReleaseAudit.scan_files([dump], %w[TestClock])

    assert_equal 1, matches.size
    assert_match(/TestClock found in #{Regexp.escape(dump)}/, matches.first)
  end

  def test_scanFiles_cleanDump_reportsNoMatches
    dump = write('dump.txt', "0001: new-instance v0, Ldev/tandem/app/MainActivity;\n")

    assert_empty ReleaseAudit.scan_files([dump], %w[TestClock SoftwareIdentityKeyStore])
  end

  # --- bundle contents ---

  def app_skeleton
    write('Tandem.app/Contents/MacOS/TandemApp', MACHO_MAGIC)
    write('Tandem.app/Contents/PlugIns/TandemShare.appex/Contents/MacOS/TandemShare', MACHO_MAGIC)
    write('Tandem.app/Contents/Resources/README.md', 'not a binary')
    File.join(@tmp, 'Tandem.app')
  end

  def test_bundleViolations_wellFormedBundle_exitsZero
    assert_empty ReleaseAudit.bundle_violations(app_skeleton)
  end

  def test_bundleViolations_extraExecutableInResources_reportsUnexpectedExecutable
    app = app_skeleton
    write('Tandem.app/Contents/Resources/helper', MACHO_MAGIC)

    violations = ReleaseAudit.bundle_violations(app)

    assert(violations.any? { |v| v.include?('unexpected executable') && v.include?('Resources/helper') })
  end

  def test_bundleViolations_xctestBundlePresent_reportsUnexpectedXctest
    app = app_skeleton
    write('Tandem.app/Contents/PlugIns/TandemUITests.xctest/Contents/MacOS/TandemUITests', MACHO_MAGIC)

    violations = ReleaseAudit.bundle_violations(app)

    assert(violations.any? { |v| v.include?('.xctest') })
  end

  def test_bundleViolations_extraEntryInContentsMacOS_reportsCountMismatch
    app = app_skeleton
    write('Tandem.app/Contents/MacOS/helper-tool', MACHO_MAGIC)

    violations = ReleaseAudit.bundle_violations(app)

    assert(violations.any? { |v| v.include?('Contents/MacOS has 2 entries') })
  end

  def test_bundleViolations_pluginNotAppex_reportsNotAnAppexBundle
    app = app_skeleton
    write('Tandem.app/Contents/PlugIns/Helper.framework/helper', MACHO_MAGIC)

    violations = ReleaseAudit.bundle_violations(app)

    assert(violations.any? { |v| v.include?('is not an .appex bundle') })
  end
end
