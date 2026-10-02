# frozen_string_literal: true

# ruby tools/release-audit/test/proto_descriptor_check_test.rb
#
# E71-09 tdd:
#   ci: protoDescriptors_debugVersusRelease_byteIdentical

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../check-proto-descriptors'

class ProtoDescriptorCheckTest < Minitest::Test
  def with_trees(debug_files, release_files)
    Dir.mktmpdir do |dir|
      debug = File.join(dir, 'debug')
      release = File.join(dir, 'release')
      { debug => debug_files, release => release_files }.each do |root, files|
        files.each do |relative, content|
          path = File.join(root, relative)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, content)
        end
      end
      yield debug, release
    end
  end

  def test_protoDescriptors_debugVersusRelease_byteIdentical
    with_trees({ 'a/Envelope.class' => "\x01\x02", 'Pairing.class' => 'p' },
               { 'a/Envelope.class' => "\x01\x02", 'Pairing.class' => 'p' }) do |debug, release|
      assert_empty ProtoDescriptorCheck.check(debug, release)
    end
  end

  def test_protoDescriptors_differingBytes_checkFailsNamingFile
    with_trees({ 'Envelope.class' => 'debug' }, { 'Envelope.class' => 'release' }) do |debug, release|
      violations = ProtoDescriptorCheck.check(debug, release)

      assert(violations.any? { |v| v.include?('Envelope.class') && v.include?('differs') })
    end
  end

  def test_protoDescriptors_debugOnlyFile_checkFailsNamingFile
    with_trees({ 'Envelope.class' => 'e', 'DebugEcho.class' => 'd' }, { 'Envelope.class' => 'e' }) do |debug, release|
      violations = ProtoDescriptorCheck.check(debug, release)

      assert(violations.any? { |v| v.include?('DebugEcho.class') && v.include?('only in the debug build') })
    end
  end

  def test_protoDescriptors_emptyTrees_checkFails
    with_trees({}, {}) do |debug, release|
      FileUtils.mkdir_p([debug, release])

      refute_empty ProtoDescriptorCheck.check(debug, release)
    end
  end
end
