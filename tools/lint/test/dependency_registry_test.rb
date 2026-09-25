# frozen_string_literal: true

# E00-29 tdd:
#   ci: licenseCheck_gplDependencyFixture_exitsNonZero
#   ci: dependencyRegistry_newDependencyWithoutJustificationEntry_exitsNonZero

require 'minitest/autorun'
require_relative '../dependency_registry'

class DependencyRegistryTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/dependency-registry', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  def test_dependencyRegistry_realRepo_exitsZero
    errors = DependencyRegistry.check(REPO_ROOT)

    assert_empty errors
  end

  def test_licenseCheck_gplDependencyFixture_exitsNonZero
    errors = DependencyRegistry.check(fixture('gpl-license'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('org.example:gpl-library') && e.include?('GPL-3.0') },
           "expected a GPL-3.0 license error, got: #{errors.inspect}")
  end

  def test_dependencyRegistry_newDependencyWithoutJustificationEntry_exitsNonZero
    errors = DependencyRegistry.check(fixture('missing-entry'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('org.example:unregistered-library') && e.include?('no entry') },
           "expected a missing-entry error, got: #{errors.inspect}")
  end

  def test_licenseCheck_gplDependencyFixture_swiftPlatform_exitsNonZero
    errors = DependencyRegistry.check(fixture('gpl-license-swift'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('gpl-swift-package') && e.include?('GPL-3.0') },
           "expected a GPL-3.0 license error, got: #{errors.inspect}")
  end

  def test_dependencyRegistry_swiftDependencyWithoutJustificationEntry_exitsNonZero
    errors = DependencyRegistry.check(fixture('missing-swift-entry'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('unregistered-swift-package') && e.include?('no entry') },
           "expected a missing-entry error, got: #{errors.inspect}")
  end
end
