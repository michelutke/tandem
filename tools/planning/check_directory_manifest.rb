#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-01: verifies the monorepo directory skeleton (PRD <structural-decomposition> plus the
# test-support additions listed on E00-01) against a checked-in manifest, and that every leaf
# module directory has a README.md naming its owning capability IDs.
#
#   ruby tools/planning/check_directory_manifest.rb            # check this repo
#   ruby tools/planning/check_directory_manifest.rb <repo-root> # check another checkout
#
# Fails (non-zero exit) if:
#   - a directory listed in the manifest is missing, or an unlisted directory exists under one
#     of ROOTS ("tree does not match manifest exactly")
#   - a leaf directory (one with no manifested subdirectories) has no README.md, or its README.md
#     names no capability ID (a PRD `F-<n>.<n>` feature or an `E<epic>-<n>` issue)

require 'set'
require 'shellwords'
require 'open3'

module DirectoryManifestCheck
  ROOTS = %w[
    android macos protocol
    tools/audit tools/conformance tools/pcap-audit tools/mitm-lab tools/fuzz
    tools/companion-app tools/log-audit tools/vectors
    docs/testing
  ].freeze

  CAPABILITY_ID = /\b(?:F-\d+\.\d+|E\d+-\d+)\b/.freeze
  MANIFEST_RELATIVE = 'tools/planning/directory-manifest.txt'

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(repo_root, roots: ROOTS, manifest_path: File.join(repo_root, MANIFEST_RELATIVE))
    repo_root = File.expand_path(repo_root)
    manifest = read_manifest(manifest_path)
    actual = find_dirs(repo_root, roots)

    errors = []
    missing = (manifest - actual).sort
    leaves = manifest.select { |dir| leaf?(dir, manifest) }
    # Anything inside a leaf module (sources, build files) is the module's own business.
    extra = (actual - manifest).reject { |dir| leaves.any? { |leaf| dir.start_with?("#{leaf}/") } }.sort
    errors << "missing directories (in manifest, not on disk):\n#{list(missing)}" unless missing.empty?
    errors << "unexpected directories (on disk, not in manifest):\n#{list(extra)}" unless extra.empty?
    errors.concat(readme_errors(repo_root, manifest))
    errors
  end

  def read_manifest(manifest_path)
    File.readlines(manifest_path).map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.to_set
  end

  def find_dirs(repo_root, roots)
    roots.each_with_object(Set.new) do |root, set|
      abs = File.join(repo_root, root)
      next unless Dir.exist?(abs)

      dirs = `find #{Shellwords.escape(abs)} -type d`.lines.map { |l| l.strip.delete_prefix("#{repo_root}/") }
      (dirs - git_ignored(repo_root, dirs)).each { |d| set << d }
    end
  end

  # Build outputs and caches (.gradle/, build/, .build/, …) are gitignored and not part of the tree.
  def git_ignored(repo_root, dirs)
    return [] if dirs.empty? || !system('git', '-C', repo_root, 'rev-parse', '--git-dir', out: File::NULL, err: File::NULL)

    out, = Open3.capture2('git', '-C', repo_root, 'check-ignore', '--stdin', stdin_data: dirs.map { |d| "#{d}/" }.join("\n"))
    out.lines.map { |l| l.strip.chomp('/') }
  end

  def leaf?(dir, all_dirs)
    all_dirs.none? { |other| other != dir && other.start_with?("#{dir}/") }
  end

  def readme_errors(repo_root, manifest)
    manifest.select { |dir| leaf?(dir, manifest) }.sort.filter_map do |dir|
      readme = File.join(repo_root, dir, 'README.md')
      if !File.exist?(readme)
        "#{dir}: leaf module directory has no README.md"
      elsif !CAPABILITY_ID.match?(File.read(readme))
        "#{dir}/README.md: names no capability ID (expected an F-<n>.<n> or E<epic>-<n> reference)"
      end
    end
  end

  def list(paths) = paths.map { |p| "  #{p}" }.join("\n")
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path(ARGV[0] || File.join(__dir__, '../..'))
  errors = DirectoryManifestCheck.check(root)
  if errors.empty?
    puts 'directory manifest check: OK'
    exit 0
  else
    warn "directory manifest check: FAILED\n\n#{errors.join("\n\n")}"
    exit 1
  end
end
