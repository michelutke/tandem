#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-29: license gate + dependency register for both trees.
#
#   ruby tools/lint/dependency_registry.rb            # check this repo
#   ruby tools/lint/dependency_registry.rb <repo-root> # check another checkout
#
# Every `[libraries]` entry in android/gradle/libs.versions.toml and every `.package(url:)` in a
# macos/Packages/*/Package.swift is a "direct dependency" and must have a row in docs/dependencies.md
# naming an allowed license. Fails (non-zero exit) if:
#   - a direct dependency has no row in docs/dependencies.md
#   - a row's license is not on ALLOWED_LICENSES (GPL, AGPL, LGPL, SSPL, or anything unlisted)
#
# Transitive dependencies (covered by verification-metadata.xml / Package.resolved) don't need a row.

require 'set'

module DependencyRegistry
  # Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ISC, Zlib per D-32. EPL-2.0 and EPL-1.0 are added
  # for the pre-existing, test-only JUnit 5 (Jupiter + Vintage) and JUnit 4 dependencies
  # (CLAUDE.md mandates JUnit5 as the `unit` test harness; JUnit 4 arrives transitively via
  # Robolectric/androidx.test, which still speak JUnit 4); see docs/dependencies.md for the
  # reasoning. This is a documented deviation from D-32's literal list, not a silent substitution.
  ALLOWED_LICENSES = %w[Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC Zlib EPL-2.0 EPL-1.0].freeze

  LIBS_VERSIONS_TOML = 'android/gradle/libs.versions.toml'
  PACKAGES_GLOB = 'macos/Packages/*/Package.swift'
  REGISTER = 'docs/dependencies.md'

  LIBRARY_LINE = /group\s*=\s*"([^"]+)".*name\s*=\s*"([^"]+)"|name\s*=\s*"([^"]+)".*group\s*=\s*"([^"]+)"/.freeze
  SWIFT_PACKAGE_URL = /\.package\(\s*(?:name:\s*"[^"]+",\s*)?url:\s*"([^"]+)"/.freeze
  TABLE_ROW = /\A\s*\|(.+)\|\s*\z/.freeze
  SEPARATOR_CELL = /\A:?-+:?\z/.freeze

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(repo_root)
    dependencies = android_dependencies(repo_root) + swift_dependencies(repo_root)
    register = read_register(File.join(repo_root, REGISTER))

    errors = []
    dependencies.each do |dep|
      license = register[dep]
      if license.nil?
        errors << "#{dep}: no entry in #{REGISTER} (every direct dependency needs a row with its license)"
      elsif !ALLOWED_LICENSES.include?(license)
        errors << "#{dep}: license '#{license}' is not on the allowlist (#{ALLOWED_LICENSES.join(', ')})"
      end
    end
    errors
  end

  def android_dependencies(repo_root)
    path = File.join(repo_root, LIBS_VERSIONS_TOML)
    return [] unless File.exist?(path)

    in_libraries = false
    File.readlines(path).each_with_object([]) do |line, deps|
      stripped = line.strip
      if stripped.start_with?('[')
        in_libraries = (stripped == '[libraries]')
        next
      end
      next unless in_libraries

      match = LIBRARY_LINE.match(stripped)
      next unless match

      group = match[1] || match[4]
      name = match[2] || match[3]
      deps << "#{group}:#{name}" if group && name
    end
  end

  def swift_dependencies(repo_root)
    Dir.glob(File.join(repo_root, PACKAGES_GLOB)).sort.each_with_object([]) do |manifest, deps|
      File.foreach(manifest) do |line|
        match = SWIFT_PACKAGE_URL.match(line)
        next unless match

        deps << File.basename(match[1]).delete_suffix('.git')
      end
    end
  end

  # Parses a `| Dependency | License | Purpose | Issue |` Markdown table (any number of columns
  # after License; only the first two are read). Returns { dependency => license }.
  def read_register(path)
    return {} unless File.exist?(path)

    File.readlines(path).each_with_object({}) do |line, register|
      match = TABLE_ROW.match(line)
      next unless match

      cells = match[1].split('|').map(&:strip)
      next if cells.size < 2
      next if cells.all? { |cell| SEPARATOR_CELL.match?(cell) }
      next if cells.first.casecmp('Dependency').zero?

      dependency = cells[0].delete_prefix('`').delete_suffix('`')
      register[dependency] = cells[1]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path(ARGV[0] || File.join(__dir__, '..', '..'))
  errors = DependencyRegistry.check(repo_root)

  if errors.empty?
    puts 'Dependency registry / license gate: OK'
    exit 0
  else
    warn "Dependency registry / license gate: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
