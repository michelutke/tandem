#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby tools/planning/test/secret_scan_test.rb
#
# Exercises the checked-in .gitleaks.toml against the real `gitleaks` binary (brew install
# gitleaks). Skips if gitleaks isn't installed rather than failing unrelated test runs.
#
# tdd (E00-16):
#   ci: secretScan_privateKeyPemFixture_jobFails
#   ci: secretScan_addedThenRemovedInSamePr_stillDetected
#   ci: secretScan_allowlistedVectorFixture_notFlagged

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'open3'

class SecretScanTest < Minitest::Test
  CONFIG_PATH = File.expand_path('../../../.gitleaks.toml', __dir__)
  FAKE_PRIVATE_KEY = <<~PEM
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEA1c7+9z5Preqinj/eD/w3EtDCsxT5CD9EmyfP6PT1xr/AGKZW
    BwSjc4A48qBfxSlZgYVR8SbrfvGnU8T4V1kA4hLLONcyLD4t1qYT8fHz1Q1q3q3F
    FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE
    -----END RSA PRIVATE KEY-----
  PEM
  FAKE_AWS_KEY = 'AKIAABCDEFGHIJKLMNOP'

  def setup
    skip 'gitleaks not installed (brew install gitleaks)' unless system('command -v gitleaks >/dev/null 2>&1')
    @tmp = Dir.mktmpdir('secret-scan')
    Dir.chdir(@tmp) do
      run!('git', 'init', '-q')
      run!('git', 'config', 'user.email', 'test@test.local')
      run!('git', 'config', 'user.name', 'test')
    end
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def run!(*cmd)
    _out, status = Open3.capture2(*cmd, chdir: @tmp)
    raise "#{cmd.join(' ')} failed" unless status.success?
  end

  def commit_file(path, contents, message:)
    full = File.join(@tmp, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
    run!('git', '-C', @tmp, 'add', path)
    run!('git', '-C', @tmp, 'commit', '-q', '-m', message)
  end

  def gitleaks_detect
    Open3.capture2e('gitleaks', 'detect', '--source', @tmp, '--config', CONFIG_PATH, '--no-banner')
  end

  def test_secretScan_privateKeyPemFixture_jobFails
    commit_file('elsewhere/fake.pem', FAKE_PRIVATE_KEY, message: 'add fixture')

    output, status = gitleaks_detect

    refute status.success?, "expected gitleaks to fail on a private key fixture, got:\n#{output}"
  end

  def test_secretScan_addedThenRemovedInSamePr_stillDetected
    commit_file('secret.txt', "#{FAKE_AWS_KEY}\n", message: 'oops added a secret')
    run!('git', '-C', @tmp, 'rm', '-q', 'secret.txt')
    run!('git', '-C', @tmp, 'commit', '-q', '-m', 'remove secret')
    refute File.exist?(File.join(@tmp, 'secret.txt'))

    output, status = gitleaks_detect

    refute status.success?, "expected gitleaks to still find the removed secret in history, got:\n#{output}"
    assert_includes output, 'leaks found: 1'
  end

  def test_secretScan_allowlistedVectorFixture_notFlagged
    commit_file('protocol/vectors/fake.pem', FAKE_PRIVATE_KEY, message: 'add allowlisted fixture')

    output, status = gitleaks_detect

    assert status.success?, "expected the protocol/vectors/** fixture to be allowlisted, got:\n#{output}"
  end
end
