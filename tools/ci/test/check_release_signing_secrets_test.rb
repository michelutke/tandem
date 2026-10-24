# frozen_string_literal: true

# E71-11 tdd:
#   ci: releaseSigningSecrets_pullRequestWorkflow_notAvailable

require 'minitest/autorun'
require_relative '../check_release_signing_secrets'

class CheckReleaseSigningSecretsTest < Minitest::Test
  FIXTURES = File.expand_path('../fixtures/release-signing-secrets', __dir__)
  REPO_ROOT = File.expand_path('../../..', __dir__)

  def fixture(name)
    File.join(FIXTURES, name)
  end

  def test_releaseSigningSecrets_pullRequestWorkflow_notAvailable
    errors = ReleaseSigningSecrets.check_file(fixture('pull-request-reads-keystore.yml'))

    assert(errors.any? { |e| e.include?('pull_request') },
           "expected a trigger error, got: #{errors.inspect}")
  end

  def test_releaseSigningSecrets_branchPushWorkflow_notAvailable
    errors = ReleaseSigningSecrets.check_file(fixture('branch-push-reads-keystore.yml'))

    refute_empty errors
  end

  def test_releaseSigningSecrets_jobWithoutReleaseEnvironment_checkFails
    errors = ReleaseSigningSecrets.check_file(fixture('tag-push-no-environment.yml'))

    assert(errors.any? { |e| e.include?("environment 'release'") },
           "expected an environment error, got: #{errors.inspect}")
  end

  def test_releaseSigningSecrets_secretsInheritOutsideRelease_checkFails
    errors = ReleaseSigningSecrets.check_file(fixture('pull-request-secrets-inherit.yml'))

    refute_empty errors
  end

  def test_releaseSigningSecrets_tagPushReleaseEnvironment_passes
    errors = ReleaseSigningSecrets.check_file(fixture('tag-push-release-environment.yml'))

    assert_empty errors
  end

  def test_releaseSigningSecrets_realRepoWorkflows_pass
    errors = ReleaseSigningSecrets.check(File.join(REPO_ROOT, '.github', 'workflows'))

    assert_empty errors
  end

  def test_releaseSigningSecrets_realRepo_hasReleaseWorkflowUsingSigningSecrets
    release = File.join(REPO_ROOT, '.github', 'workflows', 'release.yml')

    assert File.exist?(release), 'release.yml must exist'
    refute_empty ReleaseSigningSecrets.signing_secret_refs(File.read(release))
  end
end
