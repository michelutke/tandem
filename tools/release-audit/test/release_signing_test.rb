# frozen_string_literal: true

# ruby tools/release-audit/test/release_signing_test.rb
#
# E71-11 tdd:
#   ci: releaseSigningCheck_unsignedApk_apksignerVerifyFails
#   ci: releaseSigningCheck_apkSignedWithDebugKey_exitsNonZero
#   ci: releaseSigningCheck_tamperedMacApp_codesignVerifyFails
#   ci: releaseSigningCheck_notarizationEnabledWithoutTicket_staplerValidateFails
#
# apksigner, codesign and xcrun are replaced by stub scripts that print what the real tools print,
# so the checker's decisions run on any host. The real tools run against real artifacts in
# android.yml (debug APK), macos.yml (ad hoc signed and tampered .app) and release.yml.

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class ReleaseSigningTest < Minitest::Test
  TOOL = File.expand_path('../verify-release-signing.rb', __dir__)

  RELEASE_CERTS = <<~OUT
    Signer #1 certificate DN: CN=Tandem Release, O=Tandem, C=CH
    Signer #1 certificate SHA-256 digest: 3f0c2b4a9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a
  OUT
  DEBUG_CERTS = <<~OUT
    Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
    Signer #1 certificate SHA-256 digest: 9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b
  OUT

  def setup
    @bin = Dir.mktmpdir('release-signing-stubs')
    @artifact = File.join(@bin, 'artifact')
    FileUtils.touch(@artifact)
  end

  def teardown
    FileUtils.rm_rf(@bin)
  end

  def stub(name, stdout: '', stderr: '', status: 0)
    path = File.join(@bin, name)
    File.write(path, <<~SH)
      #!/bin/sh
      echo "$0 $*" >> "#{@bin}/calls.log"
      cat <<'STDOUT'
      #{stdout.chomp}
      STDOUT
      echo '#{stderr}' >&2
      exit #{status}
    SH
    File.chmod(0o755, path)
    path
  end

  def run_tool(*args, env: {})
    Open3.capture3(env, 'ruby', TOOL, *args)
  end

  def calls
    File.exist?(File.join(@bin, 'calls.log')) ? File.read(File.join(@bin, 'calls.log')) : ''
  end

  def test_releaseSigningCheck_unsignedApk_apksignerVerifyFails
    apksigner = stub('apksigner', stderr: 'DOES NOT VERIFY. ERROR: Missing META-INF/MANIFEST.MF', status: 1)

    _out, err, status = run_tool('apk', @artifact, env: { 'APKSIGNER' => apksigner })

    refute_predicate status, :success?
    assert_includes err, 'apksigner verify failed'
    assert_includes calls, "verify --print-certs #{@artifact}"
  end

  def test_releaseSigningCheck_apkSignedWithDebugKey_exitsNonZero
    apksigner = stub('apksigner', stdout: DEBUG_CERTS)

    _out, err, status = run_tool('apk', @artifact, env: { 'APKSIGNER' => apksigner })

    refute_predicate status, :success?
    assert_includes err, 'Android Debug'
  end

  def test_releaseSigningCheck_apkWithNoSignerLines_exitsNonZero
    apksigner = stub('apksigner', stdout: 'Verifies')

    _out, err, status = run_tool('apk', @artifact, env: { 'APKSIGNER' => apksigner })

    refute_predicate status, :success?
    assert_includes err, 'no signer certificate'
  end

  def test_releaseSigningCheck_apkSignedWithReleaseKey_exitsZero
    apksigner = stub('apksigner', stdout: RELEASE_CERTS)

    out, _err, status = run_tool('apk', @artifact, env: { 'APKSIGNER' => apksigner })

    assert_predicate status, :success?
    assert_includes out, 'CN=Tandem Release'
  end

  def test_releaseSigningCheck_expectedCertDigestMismatch_exitsNonZero
    apksigner = stub('apksigner', stdout: RELEASE_CERTS)

    _out, err, status = run_tool('apk', @artifact, '--expect-sha256', 'ab' * 32, env: { 'APKSIGNER' => apksigner })

    refute_predicate status, :success?
    assert_includes err, 'expected signer'
  end

  def test_releaseSigningCheck_tamperedMacApp_codesignVerifyFails
    codesign = stub('codesign', stderr: 'a sealed resource is missing or invalid', status: 1)

    _out, err, status = run_tool('mac-app', @artifact, env: { 'CODESIGN' => codesign })

    refute_predicate status, :success?
    assert_includes err, 'codesign verify failed'
    assert_includes calls, "--verify --deep --strict --verbose=2 #{@artifact}"
  end

  def test_releaseSigningCheck_signedMacAppWithoutNotarization_exitsZeroWithoutStapler
    codesign = stub('codesign', stderr: 'valid on disk')
    xcrun = stub('xcrun', status: 1)

    _out, _err, status = run_tool('mac-app', @artifact, env: { 'CODESIGN' => codesign, 'XCRUN' => xcrun })

    assert_predicate status, :success?
    refute_includes calls, 'stapler'
  end

  def test_releaseSigningCheck_notarizationEnabledWithoutTicket_staplerValidateFails
    codesign = stub('codesign', stderr: 'valid on disk')
    xcrun = stub('xcrun', stdout: 'Processing: artifact', stderr: 'artifact does not have a ticket stapled to it.', status: 65)

    _out, err, status = run_tool('mac-app', @artifact, '--notarized', env: { 'CODESIGN' => codesign, 'XCRUN' => xcrun })

    refute_predicate status, :success?
    assert_includes err, 'stapler validate failed'
    assert_includes calls, "stapler validate #{@artifact}"
  end

  def test_releaseSigningCheck_notarizedAndStapled_exitsZero
    codesign = stub('codesign', stderr: 'valid on disk')
    xcrun = stub('xcrun', stdout: 'The validate action worked!')

    _out, _err, status = run_tool('mac-app', @artifact, '--notarized', env: { 'CODESIGN' => codesign, 'XCRUN' => xcrun })

    assert_predicate status, :success?
  end

  def test_releaseSigningCheck_missingArtifact_exitsNonZero
    _out, err, status = run_tool('apk', File.join(@bin, 'nope.apk'))

    refute_predicate status, :success?
    assert_includes err, 'not found'
  end
end
