# frozen_string_literal: true

require 'json'

# macos/Package.resolved (the aggregate test manifest) must pin every dependency to the same
# revision and version as each macos/Packages/*/Package.resolved.
module SwiftResolvedSync
  ROOT = File.expand_path('../..', __dir__)
  AGGREGATE = 'macos/Package.resolved'
  PACKAGE_GLOB = 'macos/Packages/*/Package.resolved'

  def self.pins(path)
    JSON.parse(File.read(path)).fetch('pins').to_h do |pin|
      [pin.fetch('identity'), pin.fetch('state').slice('revision', 'version')]
    end
  end

  def self.errors(aggregate_path, package_paths)
    aggregate = pins(aggregate_path)
    package_paths.flat_map do |path|
      pins(path).filter_map do |identity, state|
        next if aggregate[identity] == state

        "#{path}: #{identity} pinned to #{state.inspect}, #{aggregate_path} has #{aggregate[identity].inspect}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = SwiftResolvedSync::ROOT
  errors = SwiftResolvedSync.errors(File.join(root, SwiftResolvedSync::AGGREGATE),
                                    Dir.glob(File.join(root, SwiftResolvedSync::PACKAGE_GLOB)).sort)
  errors.each { |error| warn error }
  exit(errors.empty? ? 0 : 1)
end
