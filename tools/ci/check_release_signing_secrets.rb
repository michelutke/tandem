#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-11: release signing secrets (Android keystore, Developer ID certificate, notary credentials)
# may be read only by a workflow that runs on tag pushes alone, and only by jobs bound to the
# `release` environment (which carries the required reviewer and the protected-tag rule, see
# docs/security/release-signing.md). Fails if any other workflow, or any job outside that
# environment, references one of those secrets or passes `secrets: inherit`.
#
#   ruby tools/ci/check_release_signing_secrets.rb             # check .github/workflows
#   ruby tools/ci/check_release_signing_secrets.rb <directory> # check another workflows directory

require 'yaml'

module ReleaseSigningSecrets
  DEFAULT_WORKFLOWS_DIR = File.expand_path('../../.github/workflows', __dir__)
  RELEASE_ENVIRONMENT = 'release'
  SECRET_REF = /secrets\.([A-Za-z0-9_]+)/.freeze
  SIGNING_SECRET = /KEYSTORE|SIGNING|DEVELOPER_ID|NOTARY|NOTARIZ|KEY_PASSWORD|KEY_ALIAS|P12|APPLE_/.freeze

  module_function

  # Returns an array of human-readable error strings; empty means the check passes.
  def check(workflows_dir = DEFAULT_WORKFLOWS_DIR)
    Dir.glob(File.join(workflows_dir, '*.{yml,yaml}')).sort.flat_map { |file| check_file(file) }
  end

  def signing_secret_refs(text)
    text.scan(SECRET_REF).flatten.grep(SIGNING_SECRET).uniq
  end

  def check_file(file)
    workflow = YAML.safe_load(File.read(file), aliases: true) || {}
    jobs = workflow['jobs'] || {}
    exposing = jobs.select { |_name, job| exposes_signing_secrets?(job) }
    return [] if exposing.empty?

    errors = trigger_errors(file, workflow)
    exposing.each do |name, job|
      next if environment_name(job) == RELEASE_ENVIRONMENT

      errors << "#{file}: job '#{name}' reads release signing secrets but is not bound to environment " \
                "'#{RELEASE_ENVIRONMENT}'"
    end
    errors
  end

  def exposes_signing_secrets?(job)
    return false unless job.is_a?(Hash)

    job['secrets'] == 'inherit' || !signing_secret_refs(YAML.dump(job)).empty?
  end

  # Psych reads the bare YAML 1.1 key `on` as boolean true.
  def triggers(workflow)
    on = workflow.key?('on') ? workflow['on'] : workflow[true]
    case on
    when Hash then on
    when Array then on.to_h { |event| [event, nil] }
    when String then { on => nil }
    else {}
    end
  end

  def trigger_errors(file, workflow)
    events = triggers(workflow)
    errors = (events.keys - ['push']).map do |event|
      "#{file}: release signing secrets are read by a workflow triggered on '#{event}'; only tag pushes may read them"
    end
    push = events['push']
    unless push.is_a?(Hash) && push.keys == ['tags'] && !Array(push['tags']).empty?
      errors << "#{file}: release signing secrets are read on push without a tags-only filter"
    end
    errors
  end

  def environment_name(job)
    env = job['environment']
    env.is_a?(Hash) ? env['name'] : env
  end
end

if $PROGRAM_NAME == __FILE__
  errors = ReleaseSigningSecrets.check(*ARGV)
  if errors.empty?
    puts 'release signing secrets: only tag-triggered release-environment jobs read them'
  else
    warn errors
    exit 1
  end
end
