#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/lint/test/swift_package_rules_test.rb
#
# tdd (E00-15):
#   ci: packageGraphCheck_featureDependsOnFeatureFixture_exitsNonZero
#   ci: packageGraphCheck_networkImportInFeatureNotifications_exitsNonZero
#   ci: packageGraphCheck_networkImportInTandemTransport_exitsZero
#   ci: dependencyDenylist_swifterPackageAdded_exitsNonZero
#   ci: dependencyDenylist_sentryCocoaPackageAdded_exitsNonZero

require 'minitest/autorun'
require_relative '../swift-package-rules'

class SwiftPackageRulesTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/swift-packages', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  def test_packageGraphCheck_realRepoPackages_exitsZero
    errors = SwiftPackageRules.check(File.join(REPO_ROOT, 'macos', 'Packages'))

    assert_empty errors
  end

  def test_packageGraphCheck_featureDependsOnFeatureFixture_exitsNonZero
    errors = SwiftPackageRules.check(fixture('feature-depends-on-feature'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('FeatureClipboard') && e.include?('FeatureFiles') },
           "expected a feature-depends-on-feature error, got: #{errors.inspect}")
  end

  def test_packageGraphCheck_networkImportInFeatureNotifications_exitsNonZero
    errors = SwiftPackageRules.check(fixture('network-import-in-feature-notifications'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('FeatureNotifications') && e.include?('Network') },
           "expected a Network-import error, got: #{errors.inspect}")
  end

  def test_packageGraphCheck_networkImportInTandemTransport_exitsZero
    errors = SwiftPackageRules.check(fixture('network-import-in-tandem-transport'))

    assert_empty errors
  end

  def test_packageGraphCheck_testSupportDependencyOutsideTestTarget_exitsNonZero
    errors = SwiftPackageRules.check(fixture('test-support-outside-test-target'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('TandemTestSupport') },
           "expected a TandemTestSupport error, got: #{errors.inspect}")
  end

  def test_packageGraphCheck_testSupportDependencyInTestTargetOnly_exitsZero
    errors = SwiftPackageRules.check(fixture('test-support-in-test-target-only'))

    assert_empty errors
  end

  def test_dependencyDenylist_swifterPackageAdded_exitsNonZero
    errors = SwiftPackageRules.check(fixture('denylist-swifter'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('swifter') },
           "expected a denylist error naming swifter, got: #{errors.inspect}")
  end

  def test_dependencyDenylist_sentryCocoaPackageAdded_exitsNonZero
    errors = SwiftPackageRules.check(fixture('denylist-sentry-cocoa'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('sentry') },
           "expected a denylist error naming sentry, got: #{errors.inspect}")
  end
end
