#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-02: verifies `./gradlew projects` lists exactly the Android modules that are leaf
# directories in the checked-in directory manifest (tools/planning/directory-manifest.txt).
#
#   ruby tools/planning/check_gradle_projects.rb            # check this repo
#   ruby tools/planning/check_gradle_projects.rb <repo-root> # check another checkout
#
# Fails (non-zero exit) if the set of buildable Gradle projects (those with a build.gradle.kts,
# which excludes the placeholder ":core" / ":feature" parent projects Gradle creates for nested
# `include(...)` paths) does not exactly match the app/core/feature module directories under
# android/ (as opposed to every leaf directory under android/, which also covers non-module
# tooling directories like android/gradle and the android/build-logic included build).

require 'set'
require 'open3'
require_relative 'check_directory_manifest'

module CheckGradleProjects
  MANIFEST_RELATIVE = 'tools/planning/directory-manifest.txt'
  PROJECT_LINE = /Project '(?<path>:[\w:-]*)'/.freeze
  MODULE_DIR = %r{\Aandroid/(app|core/[^/]+|feature/[^/]+|lint/[^/]+|harness/[^/]+)\z}.freeze

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(repo_root, runner: method(:run_gradle_projects))
    repo_root = File.expand_path(repo_root)
    android_dir = File.join(repo_root, 'android')
    manifest = DirectoryManifestCheck.read_manifest(File.join(repo_root, MANIFEST_RELATIVE))
    expected = manifest
               .select { |dir| MODULE_DIR.match?(dir) && DirectoryManifestCheck.leaf?(dir, manifest) }
               .map { |dir| gradle_path(dir) }
               .to_set

    actual = runner.call(android_dir)

    errors = []
    missing = (expected - actual).sort
    extra = (actual - expected).sort
    errors << "modules missing from `./gradlew projects`:\n#{list(missing)}" unless missing.empty?
    errors << "unexpected buildable projects (no matching manifest module):\n#{list(extra)}" unless extra.empty?
    errors
  end

  def gradle_path(dir)
    ":#{dir.delete_prefix('android/').tr('/', ':')}"
  end

  def run_gradle_projects(android_dir)
    gradlew = File.join(android_dir, 'gradlew')
    output, status = Open3.capture2(gradlew, '-q', 'projects', '--console=plain', chdir: android_dir)
    raise "`./gradlew projects` failed:\n#{output}" unless status.success?

    parse_projects(output, android_dir)
  end

  def parse_projects(output, android_dir)
    output.scan(PROJECT_LINE).flatten.select { |path| buildable?(android_dir, path) }.to_set
  end

  def buildable?(android_dir, gradle_path)
    dir = gradle_path.delete_prefix(':').tr(':', '/')
    File.exist?(File.join(android_dir, dir, 'build.gradle.kts'))
  end

  def list(paths) = paths.map { |p| "  #{p}" }.join("\n")
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path(ARGV[0] || File.join(__dir__, '../..'))
  errors = CheckGradleProjects.check(root)
  if errors.empty?
    puts 'gradle projects check: OK'
    exit 0
  else
    warn "gradle projects check: FAILED\n\n#{errors.join("\n\n")}"
    exit 1
  end
end
