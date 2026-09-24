#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/planning/test/check_directory_manifest_test.rb
#
# tdd (E00-01):
#   ci: directoryManifestCheck_treeMatchesManifest_exitsZero
#   ci: directoryManifestCheck_missingModuleDirectory_failsListingMissingPath
#   ci: directoryManifestCheck_leafReadmeWithoutCapabilityIds_exitsNonZero

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../check_directory_manifest'

class CheckDirectoryManifestTest < Minitest::Test
  SAMPLE_MANIFEST = %w[
    sample sample/core sample/core/crypto sample/feature sample/feature/notifications
  ].freeze

  def setup
    @tmp = Dir.mktmpdir('directory-manifest-check')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def build_sample_tree(readme_text: 'F-1.1: sample capability owner.')
    FileUtils.mkdir_p(File.join(@tmp, 'sample/core/crypto'))
    FileUtils.mkdir_p(File.join(@tmp, 'sample/feature/notifications'))
    File.write(File.join(@tmp, 'sample/core/crypto/README.md'), readme_text)
    File.write(File.join(@tmp, 'sample/feature/notifications/README.md'), 'E00-01: sample.')
    manifest_path = File.join(@tmp, 'manifest.txt')
    File.write(manifest_path, "#{SAMPLE_MANIFEST.join("\n")}\n")
    manifest_path
  end

  def test_directoryManifestCheck_treeMatchesManifest_exitsZero
    manifest_path = build_sample_tree

    errors = DirectoryManifestCheck.check(@tmp, roots: %w[sample], manifest_path: manifest_path)

    assert_empty errors
  end

  def test_directoryManifestCheck_missingModuleDirectory_failsListingMissingPath
    manifest_path = build_sample_tree
    FileUtils.remove_entry(File.join(@tmp, 'sample/feature/notifications'))

    errors = DirectoryManifestCheck.check(@tmp, roots: %w[sample], manifest_path: manifest_path)

    refute_empty errors
    assert(errors.any? { |e| e.include?('sample/feature/notifications') },
           "expected an error naming the missing path, got: #{errors.inspect}")
  end

  def test_directoryManifestCheck_leafReadmeWithoutCapabilityIds_exitsNonZero
    manifest_path = build_sample_tree(readme_text: 'Owns the crypto identity module.')

    errors = DirectoryManifestCheck.check(@tmp, roots: %w[sample], manifest_path: manifest_path)

    refute_empty errors
    assert(errors.any? { |e| e.include?('sample/core/crypto/README.md') },
           "expected an error naming the README missing a capability ID, got: #{errors.inspect}")
  end

  def test_directoryManifestCheck_unexpectedDirectoryNotInManifest_failsListingExtraPath
    manifest_path = build_sample_tree
    FileUtils.mkdir_p(File.join(@tmp, 'sample/feature/clipboard'))
    File.write(File.join(@tmp, 'sample/feature/clipboard/README.md'), 'F-6.1: clipboard.')

    errors = DirectoryManifestCheck.check(@tmp, roots: %w[sample], manifest_path: manifest_path)

    refute_empty errors
    assert(errors.any? { |e| e.include?('sample/feature/clipboard') },
           "expected an error naming the unexpected path, got: #{errors.inspect}")
  end

  def test_directoryManifestCheck_sourceDirsInsideLeafModule_ignored
    manifest_path = build_sample_tree
    FileUtils.mkdir_p(File.join(@tmp, 'sample/core/crypto/src/main/kotlin'))

    errors = DirectoryManifestCheck.check(@tmp, roots: %w[sample], manifest_path: manifest_path)

    assert_empty errors
  end
end
