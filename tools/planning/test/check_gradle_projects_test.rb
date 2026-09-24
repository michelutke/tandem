#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/planning/test/check_gradle_projects_test.rb
#
# tdd (E00-02):
#   ci: gradleProjects_cleanCheckout_listMatchesDirectoryManifest

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../check_gradle_projects'

class CheckGradleProjectsTest < Minitest::Test
  SAMPLE_MANIFEST = %w[
    android android/app android/build-logic android/gradle
    android/core android/core/crypto
    android/feature android/feature/notifications
  ].freeze

  SAMPLE_GRADLEW_PROJECTS_OUTPUT = <<~OUTPUT
    Root project 'tandem-android'
    +--- Project ':app'
    +--- Project ':core'
    |    \\--- Project ':core:crypto'
    \\--- Project ':feature'
         \\--- Project ':feature:notifications'
  OUTPUT

  def setup
    @tmp = Dir.mktmpdir('gradle-projects-check')
    FileUtils.mkdir_p(File.join(@tmp, 'tools/planning'))
    File.write(File.join(@tmp, 'tools/planning/directory-manifest.txt'), "#{SAMPLE_MANIFEST.join("\n")}\n")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def touch_build_file(*relative_dir)
    path = File.join(@tmp, 'android', *relative_dir)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'build.gradle.kts'), '')
  end

  def test_gradleProjects_cleanCheckout_listMatchesDirectoryManifest
    touch_build_file('app')
    touch_build_file('core', 'crypto')
    touch_build_file('feature', 'notifications')

    runner = ->(_android_dir) { CheckGradleProjects.parse_projects(SAMPLE_GRADLEW_PROJECTS_OUTPUT, File.join(@tmp, 'android')) }
    errors = CheckGradleProjects.check(@tmp, runner: runner)

    assert_empty errors
  end

  def test_gradleProjects_buildLogicAndGradleLeaves_notExpectedAsProjects
    # android/build-logic and android/gradle are leaf manifest directories but are not modules
    # of the main build (build-logic is a separate included build; gradle/ is wrapper files),
    # so they must not be expected in `./gradlew projects` even though build-logic has its own
    # build.gradle.kts.
    touch_build_file('app')
    touch_build_file('core', 'crypto')
    touch_build_file('feature', 'notifications')
    touch_build_file('build-logic')

    runner = ->(_android_dir) { CheckGradleProjects.parse_projects(SAMPLE_GRADLEW_PROJECTS_OUTPUT, File.join(@tmp, 'android')) }
    errors = CheckGradleProjects.check(@tmp, runner: runner)

    assert_empty errors
  end

  def test_gradleProjects_missingModuleBuildFile_failsListingMissingModule
    touch_build_file('app')
    touch_build_file('core', 'crypto')
    # feature/notifications has no build.gradle.kts, so it never shows up as buildable.

    runner = ->(_android_dir) { CheckGradleProjects.parse_projects(SAMPLE_GRADLEW_PROJECTS_OUTPUT, File.join(@tmp, 'android')) }
    errors = CheckGradleProjects.check(@tmp, runner: runner)

    refute_empty errors
    assert(errors.any? { |e| e.include?(':feature:notifications') })
  end

  def test_gradleProjects_extraBuildableProjectNotInManifest_failsListingExtraModule
    touch_build_file('app')
    touch_build_file('core', 'crypto')
    touch_build_file('feature', 'notifications')
    touch_build_file('feature', 'unplanned')

    output = SAMPLE_GRADLEW_PROJECTS_OUTPUT + "     \\--- Project ':feature:unplanned'\n"
    runner = ->(_android_dir) { CheckGradleProjects.parse_projects(output, File.join(@tmp, 'android')) }
    errors = CheckGradleProjects.check(@tmp, runner: runner)

    refute_empty errors
    assert(errors.any? { |e| e.include?(':feature:unplanned') })
  end
end
