#!/usr/bin/env ruby
# frozen_string_literal: true

# E00-29: fails if any GitHub Actions workflow `uses:` step references an action by anything
# other than a full 40-hex-character commit SHA (tags and branches are mutable and can be
# repointed by whoever controls the upstream repo).
#
#   ruby tools/ci/check_actions_pinned.rb             # check .github/workflows
#   ruby tools/ci/check_actions_pinned.rb <directory> # check another workflows directory

module ActionsPinned
  DEFAULT_WORKFLOWS_DIR = File.expand_path('../../.github/workflows', __dir__)
  SHA_REF = /\A[0-9a-f]{40}\z/.freeze
  USES_LINE = /^\s*-?\s*uses:\s*(\S+)/.freeze

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(workflows_dir = DEFAULT_WORKFLOWS_DIR)
    Dir.glob(File.join(workflows_dir, '*.{yml,yaml}')).sort.flat_map { |file| check_file(file) }
  end

  def check_file(file)
    File.readlines(file).each_with_index.each_with_object([]) do |(line, index), errors|
      match = USES_LINE.match(line)
      next unless match

      uses = match[1]
      next if uses.start_with?('./', '.\\') # local composite action: not a supply-chain dependency

      ref = uses.split('@', 2)[1]
      next if ref && SHA_REF.match?(ref)

      errors << "#{file}:#{index + 1}: '#{uses}' is not pinned to a 40-character commit SHA"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  errors = ActionsPinned.check(*ARGV)

  if errors.empty?
    puts 'GitHub Actions pin check: OK'
    exit 0
  else
    warn "GitHub Actions pin check: FAILED\n\n#{errors.map { |e| "  #{e}" }.join("\n")}"
    exit 1
  end
end
