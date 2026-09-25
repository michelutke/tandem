#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/lint/test/literal_color_check_test.rb
#
# tdd (E00-32):
#   ci: featureSources_literalColor_lintFails

require 'minitest/autorun'
require_relative '../literal-color-check'

class LiteralColorCheckTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/swift', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  def test_featureSources_literalColor_lintFails
    errors = LiteralColorCheck.check(fixture('LiteralColorConstructorFixture.swift'))

    refute_empty errors
    assert(errors.any? { |e| e.include?('literal Color') }, "expected a literal Color error, got: #{errors.inspect}")
  end

  def test_featureSources_paletteColorMember_lintFails
    errors = LiteralColorCheck.check(fixture('LiteralColorPaletteMemberFixture.swift'))

    assert_equal 2, errors.size
    assert(errors.any? { |e| e.include?('Color.red') })
    assert(errors.any? { |e| e.include?('Color.blue') })
  end

  def test_featureSources_tandemColorToken_lintPasses
    errors = LiteralColorCheck.check(fixture('LiteralColorTandemTokenFixture.swift'))

    assert_empty errors
  end

  def test_featureSources_tandemDesignOwnTokenDefinitions_lintPasses
    errors = LiteralColorCheck.check(File.join(REPO_ROOT, 'macos', 'Packages', 'TandemDesign'))

    assert_empty errors
  end

  def test_realMacosSources_lintPasses
    errors = LiteralColorCheck.check(File.join(REPO_ROOT, 'macos'))

    assert_empty errors
  end
end
