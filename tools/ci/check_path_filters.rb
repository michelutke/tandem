#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-11: evaluates each workflow's `on.pull_request.paths` against a list of changed files and
# prints which workflows would run. Used by the path-filter tests; also handy before pushing:
#
#   git diff --name-only origin/main | ruby tools/ci/check_path_filters.rb
#
# Glob semantics follow GitHub Actions: `**` matches across `/`, `*` does not.

require 'yaml'

module PathFilters
  WORKFLOWS_DIR = File.expand_path('../../.github/workflows', __dir__)

  module_function

  def glob_to_regex(glob)
    body = glob.split(/(\*\*|\*)/).map do |part|
      case part
      when '**' then '.*'
      when '*' then '[^/]*'
      else Regexp.escape(part)
      end
    end.join
    /\A#{body}\z/
  end

  def pull_request_paths(workflow_file)
    doc = YAML.safe_load(File.read(workflow_file), aliases: true)
    triggers = doc['on'] || doc[true] # YAML 1.1 parses a bare `on` key as boolean true
    Array(triggers.dig('pull_request', 'paths'))
  end

  # Returns workflow names (file basenames without extension) whose pull_request paths match any
  # changed file. Workflows without a pull_request path filter run on every PR.
  def triggered(changed_files, workflows_dir: WORKFLOWS_DIR)
    Dir[File.join(workflows_dir, '*.yml')].sort.filter_map do |file|
      patterns = pull_request_paths(file)
      name = File.basename(file, '.yml')
      next name if patterns.empty?

      regexes = patterns.map { |p| glob_to_regex(p) }
      name if changed_files.any? { |f| regexes.any? { |r| r.match?(f) } }
    end
  end
end

puts PathFilters.triggered($stdin.read.split) if $PROGRAM_NAME == __FILE__
