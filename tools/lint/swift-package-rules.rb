#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-15: Swift package graph dependency rule check for macos/Packages/*.
#
#   ruby tools/lint/swift-package-rules.rb                # check macos/Packages
#   ruby tools/lint/swift-package-rules.rb <packages-dir> # check another directory of packages
#
# Reads each package's manifest via `swift package dump-package` and fails (non-zero exit) if:
#   - a `Feature*` package has a local (path) dependency on another `Feature*` package
#     (PRD module rules: "Features depend on core/* and never on each other.")
#   - a package other than TandemTransport has a source file that `import`s `Network`
#     (PRD module rules: "Only core/transport touches sockets.")
#   - a regular (non-test) target depends on the `TandemTestSupport` product
#     (TandemTestSupport is a test-support module: test-target dependency only.)
#   - a package depends on an artifact matching `dependency-denylist.txt` (HTTP/WebDAV server
#     libraries and third-party crash/analytics SDKs; invariant 2 and the cycle-4 decision).

require 'json'
require 'open3'

module SwiftPackageRules
  DEFAULT_DENYLIST_PATH = File.join(__dir__, 'dependency-denylist.txt')
  SOCKET_ONLY_PACKAGE = 'TandemTransport'
  TEST_SUPPORT_PACKAGE = 'TandemTestSupport'

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(packages_root, denylist_path: DEFAULT_DENYLIST_PATH)
    package_dirs = package_dirs(packages_root)
    denylist = read_denylist(denylist_path)
    errors = []

    package_dirs.each do |dir|
      name = File.basename(dir)
      package = dump_package(dir)

      errors.concat(feature_dependency_errors(name, package))
      errors.concat(test_support_errors(name, package))
      errors.concat(denylist_errors(name, package, denylist))
      errors.concat(import_errors(name, dir, 'Network', allowed: SOCKET_ONLY_PACKAGE))
    end

    errors
  end

  def package_dirs(packages_root)
    Dir.glob(File.join(packages_root, '*'))
       .select { |dir| File.file?(File.join(dir, 'Package.swift')) }
       .sort
  end

  def dump_package(dir)
    out, status = Open3.capture2('swift', 'package', 'dump-package', chdir: dir)
    raise "swift package dump-package failed in #{dir}" unless status.success?

    JSON.parse(out)
  end

  def local_dependency_names(package)
    (package['dependencies'] || []).flat_map do |dep|
      entries = dep['fileSystem']
      next [] unless entries

      entries.map { |entry| File.basename(entry['path']) }
    end
  end

  def feature_dependency_errors(name, package)
    return [] unless name.start_with?('Feature')

    local_dependency_names(package).select { |dep| dep.start_with?('Feature') }.map do |dep|
      "#{name}: feature package depends on feature package #{dep} " \
        '(features must depend only on core packages, never on each other)'
    end
  end

  def target_product_names(target)
    (target['dependencies'] || []).filter_map do |dep|
      dep['product']&.first || dep['byName']&.first
    end
  end

  def test_support_errors(name, package)
    (package['targets'] || []).flat_map do |target|
      next [] if target['type'] == 'test'

      target_product_names(target).select { |dep| dep.casecmp(TEST_SUPPORT_PACKAGE).zero? }.map do
        "#{name}: non-test target '#{target['name']}' depends on #{TEST_SUPPORT_PACKAGE} " \
          '(it is a test-support module: test-target dependency only)'
      end
    end
  end

  def denylist_errors(name, package, denylist)
    (package['dependencies'] || []).flat_map do |dep|
      entries = dep['sourceControl']
      next [] unless entries

      entries.flat_map do |entry|
        haystacks = [entry['identity'], entry.dig('location', 'remote', 0, 'urlString')].compact.map(&:downcase)
        denylist.select { |bad| haystacks.any? { |haystack| haystack.include?(bad) } }
                .map { |bad| "#{name}: dependency '#{entry['identity']}' matches denylisted pattern '#{bad}'" }
      end
    end
  end

  def import_errors(name, dir, module_name, allowed:)
    return [] if name == allowed

    pattern = /^\s*(?:@\w+\s+)*import\s+#{Regexp.escape(module_name)}\b/
    Dir.glob(File.join(dir, 'Sources', '**', '*.swift')).each_with_object([]) do |file, errors|
      File.foreach(file).with_index(1) do |line, lineno|
        next unless pattern.match?(line)

        errors << "#{name}: #{file}:#{lineno}: imports #{module_name} (only #{allowed} may import it)"
      end
    end
  end

  def read_denylist(path)
    return [] unless File.exist?(path)

    File.readlines(path).map(&:strip).reject { |line| line.empty? || line.start_with?('#') }.map(&:downcase)
  end
end

if $PROGRAM_NAME == __FILE__
  repo_root = File.expand_path(File.join(__dir__, '..', '..'))
  packages_root = File.expand_path(ARGV[0] || File.join(repo_root, 'macos', 'Packages'))
  errors = SwiftPackageRules.check(packages_root)

  if errors.empty?
    puts 'swift package rules check: OK'
    exit 0
  else
    warn "swift package rules check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
