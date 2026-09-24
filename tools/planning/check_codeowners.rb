#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-13: verifies .github/CODEOWNERS covers every git-tracked path (no path left unowned) and
# that every rule names at least one syntactically plausible owner.
#
#   ruby tools/planning/check_codeowners.rb            # check this repo
#   ruby tools/planning/check_codeowners.rb <repo-root> # check another checkout
#
# Supports the subset of CODEOWNERS syntax this repo uses: `*` (matches every path) and
# root-anchored directory patterns (`/dir/`, matching `dir` and everything under it). As in
# GitHub's own CODEOWNERS evaluation, the last matching pattern in the file wins.
#
# Fails (non-zero exit) if:
#   - .github/CODEOWNERS is missing
#   - a line has a pattern but no @owner (or an owner that doesn't look like a handle/team/email)
#   - a git-tracked path matches no pattern in the file

require 'shellwords'

module CheckCodeowners
  CODEOWNERS_RELATIVE = '.github/CODEOWNERS'
  OWNER = %r{\A(?:@[\w.-]+(?:/[\w.-]+)?|[^\s@]+@[^\s@]+)\z}.freeze

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(repo_root, tracked_files: nil)
    repo_root = File.expand_path(repo_root)
    codeowners_path = File.join(repo_root, CODEOWNERS_RELATIVE)
    return ["#{CODEOWNERS_RELATIVE}: file not found"] unless File.exist?(codeowners_path)

    errors = []
    rules = parse(File.readlines(codeowners_path), errors)
    tracked = tracked_files || git_ls_files(repo_root)

    unowned = tracked.reject { |path| owners_for(path, rules).any? }
    errors << "tracked paths with no CODEOWNERS entry:\n#{list(unowned.sort)}" unless unowned.empty?
    errors
  end

  def parse(lines, errors)
    lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.filter_map do |line|
      pattern, *owners = line.split(/\s+/)
      if owners.empty? || owners.any? { |o| !OWNER.match?(o) }
        errors << "#{CODEOWNERS_RELATIVE}: invalid line #{line.inspect} (pattern needs at least one @owner)"
        next
      end
      { pattern: pattern, owners: owners }
    end
  end

  def owners_for(path, rules)
    match = nil
    rules.each { |rule| match = rule if pattern_matches?(rule[:pattern], path) }
    match ? match[:owners] : []
  end

  def pattern_matches?(pattern, path)
    return true if pattern == '*'

    stripped = pattern.delete_prefix('/').delete_suffix('/')
    path == stripped || path.start_with?("#{stripped}/")
  end

  def git_ls_files(repo_root)
    `git -C #{Shellwords.escape(repo_root)} ls-files`.lines.map(&:chomp)
  end

  def list(paths) = paths.map { |p| "  #{p}" }.join("\n")
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path(ARGV[0] || File.join(__dir__, '../..'))
  errors = CheckCodeowners.check(root)
  if errors.empty?
    puts 'codeowners check: OK'
    exit 0
  else
    warn "codeowners check: FAILED\n\n#{errors.join("\n\n")}"
    exit 1
  end
end
