# frozen_string_literal: true

# E00-33: every module that applies `tandem.android.instrumented` and has androidTest sources must
# be listed in a `modules:` entry of android-instrumented.yml, which runs its managed-device tests.
module InstrumentedModules
  ROOT = File.expand_path('../..', __dir__)
  WORKFLOW = '.github/workflows/android-instrumented.yml'

  def self.modules(root = ROOT)
    Dir.glob(File.join(root, 'android/**/build.gradle.kts')).filter_map do |build_file|
      dir = File.dirname(build_file)
      next unless File.read(build_file).include?('"tandem.android.instrumented"')
      next unless Dir.exist?(File.join(dir, 'src/androidTest'))

      ":#{dir.delete_prefix(File.join(root, 'android/')).tr('/', ':')}"
    end.sort
  end

  def self.missing(workflow_text, modules)
    listed = workflow_text.lines.grep(/^\s*modules:/).flat_map { |line| line.scan(/:[\w:-]+/) }
    modules.reject { |mod| listed.include?(mod) }
  end
end

if $PROGRAM_NAME == __FILE__
  missing = InstrumentedModules.missing(File.read(File.join(InstrumentedModules::ROOT, InstrumentedModules::WORKFLOW)), InstrumentedModules.modules)
  missing.each { |mod| warn "#{InstrumentedModules::WORKFLOW}: #{mod} instrumented tests are not run" }
  exit(missing.empty? ? 0 : 1)
end
