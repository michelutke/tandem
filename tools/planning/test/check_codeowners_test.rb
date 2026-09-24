#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/planning/test/check_codeowners_test.rb
#
# tdd (E00-13):
#   ci: codeownersCheck_trackedPathWithoutOwner_exitsNonZero

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../check_codeowners'

class CheckCodeownersTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir('codeowners-check')
    FileUtils.mkdir_p(File.join(@tmp, '.github'))
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def write_codeowners(text)
    File.write(File.join(@tmp, '.github/CODEOWNERS'), text)
  end

  def test_codeownersCheck_trackedPathWithoutOwner_exitsNonZero
    write_codeowners(<<~CODEOWNERS)
      /android/ @michelutke
      /macos/ @michelutke
    CODEOWNERS

    errors = CheckCodeowners.check(@tmp, tracked_files: %w[android/app/Foo.kt docs/PRD.md])

    refute_empty errors
    assert(errors.any? { |e| e.include?('docs/PRD.md') })
  end

  def test_codeownersCheck_catchAllCoversEveryTrackedPath_exitsZero
    write_codeowners(<<~CODEOWNERS)
      * @michelutke

      /android/ @michelutke
      /tools/ @michelutke
    CODEOWNERS

    errors = CheckCodeowners.check(@tmp, tracked_files: %w[android/app/Foo.kt docs/PRD.md tools/planning/sync_issues.rb])

    assert_empty errors
  end

  def test_codeownersCheck_missingFile_reportsMissing
    errors = CheckCodeowners.check(@tmp, tracked_files: %w[docs/PRD.md])

    refute_empty errors
    assert(errors.any? { |e| e.include?('CODEOWNERS') })
  end

  def test_codeownersCheck_lineWithNoOwner_reportsInvalidLine
    write_codeowners(<<~CODEOWNERS)
      * @michelutke
      /android/
    CODEOWNERS

    errors = CheckCodeowners.check(@tmp, tracked_files: %w[android/app/Foo.kt])

    refute_empty errors
    assert(errors.any? { |e| e.include?('invalid line') })
  end
end
