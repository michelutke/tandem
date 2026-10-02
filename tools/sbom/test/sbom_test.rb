# frozen_string_literal: true

# E71-10 tdd:
#   ci: sbomGeneration_gradleAndSwiftPm_bothDependencyTreesListed
#   ci: sbomCheck_dependencyChangedWithoutRegeneration_exitsNonZero
#   ci: vulnScan_fixtureWithKnownCriticalCve_exitsNonZero
#   ci: sbom_everyComponent_hasLicenseField

require 'date'
require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../sbom'

class SbomTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)
  FIXTURE_REPO = File.join(FIXTURES, 'repo')
  REPO_ROOT = File.expand_path('../../..', __dir__)
  TODAY = Date.new(2026, 10, 1)

  def sbom_for(root) = JSON.parse(Sbom.render(root))

  def advisories = JSON.parse(File.read(File.join(FIXTURES, 'advisories.json')))

  def with_fixture_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("#{FIXTURE_REPO}/.", dir)
      yield dir
    end
  end

  def test_sbomGeneration_gradleAndSwiftPm_bothDependencyTreesListed
    purls = sbom_for(FIXTURE_REPO)['components'].map { |c| c['purl'] }

    assert_includes purls, 'pkg:maven/org.example/vulnerable-lib@1.0.0'
    assert_includes purls, 'pkg:swift/github.com/example/swift-thing@3.1.0'
  end

  def test_sbomGeneration_realRepo_listsEveryGradleAndSwiftPmPin
    purls = sbom_for(REPO_ROOT)['components'].map { |c| c['purl'] }

    assert(purls.any? { |p| p.start_with?('pkg:maven/') })
    assert(purls.any? { |p| p.start_with?('pkg:swift/github.com/apple/swift-crypto@') })
  end

  def test_sbomCheck_realRepo_exitsZero
    assert_empty Sbom.check(REPO_ROOT)
  end

  def test_sbomCheck_dependencyChangedWithoutRegeneration_exitsNonZero
    with_fixture_copy do |dir|
      File.write(File.join(dir, Sbom::SBOM_PATH), Sbom.render(dir))
      File.write(File.join(dir, Sbom::LICENSE_EXCEPTIONS_PATH), "org.example:gpl-lib fixture\n")
      assert_empty Sbom.check(dir)

      resolved = Dir.glob(File.join(dir, 'macos/Packages/*/Package.resolved')).first
      File.write(resolved, File.read(resolved).sub('3.1.0', '3.2.0'))

      errors = Sbom.check(dir)

      assert(errors.any? { |e| e.include?('stale') }, errors.inspect)
    end
  end

  def test_sbomCheck_missingSbom_exitsNonZero
    with_fixture_copy do |dir|
      refute_empty Sbom.check(dir)
    end
  end

  def test_sbom_everyComponent_hasLicenseField
    sbom = sbom_for(REPO_ROOT)

    refute_empty sbom['components']
    sbom['components'].each do |component|
      license = component.dig('licenses', 0, 'license', 'id')
      refute_nil license, "#{component['purl']} has no license"
      refute_equal 'UNKNOWN', license, "#{component['purl']} license not mapped in tools/sbom/licenses.txt"
    end
  end

  def test_licenseGate_disallowedLicenseWithoutException_exitsNonZero
    with_fixture_copy do |dir|
      File.write(File.join(dir, Sbom::SBOM_PATH), Sbom.render(dir))

      errors = Sbom.check(dir)

      assert(errors.any? { |e| e.include?('org.example/gpl-lib') && e.include?('GPL-3.0-only') }, errors.inspect)
    end
  end

  def test_vulnScan_fixtureWithKnownCriticalCve_exitsNonZero
    errors = Sbom.scan(sbom_for(FIXTURE_REPO), advisories, [], TODAY)

    assert_equal 1, errors.size
    assert_includes errors.first, 'GHSA-fixture-crit'
  end

  def test_vulnScan_criticalCveWithValidWaiver_exitsZero
    waivers = [{ 'id' => 'GHSA-fixture-crit', 'reason' => 'not reachable', 'expires' => '2026-12-31' }]

    assert_empty Sbom.scan(sbom_for(FIXTURE_REPO), advisories, waivers, TODAY)
  end

  def test_vulnScan_criticalCveWithExpiredWaiver_exitsNonZero
    waivers = [{ 'id' => 'GHSA-fixture-crit', 'reason' => 'not reachable', 'expires' => '2026-09-30' }]

    errors = Sbom.scan(sbom_for(FIXTURE_REPO), advisories, waivers, TODAY)

    assert(errors.any? { |e| e.include?('expired') })
    assert(errors.any? { |e| e.include?('not waived') })
  end

  def test_run_scanWithAdvisoriesFixture_returnsOne
    with_fixture_copy do |dir|
      File.write(File.join(dir, Sbom::SBOM_PATH), Sbom.render(dir))

      status = Sbom.run(['scan', '--advisories', File.join(FIXTURES, 'advisories.json')], dir, today: TODAY)

      assert_equal 1, status
    end
  end

  def test_waiversFile_realRepo_entriesHaveReasonAndExpiry
    Sbom.read_waivers(REPO_ROOT).each do |waiver|
      %w[id reason expires].each { |key| refute_nil waiver[key], "waiver missing #{key}" }
    end
  end
end
