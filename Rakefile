# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require_relative "lib/kitsune/kit/version"

RSpec::Core::RakeTask.new(:spec) do |task|
  task.exclude_pattern = "spec/{integration,e2e}/**/*_spec.rb"
end
Rake::Task[:spec].enhance do
  sh Gem.ruby, "script/verify-core-coverage"
end

desc "Run the complete test suite"
task test: :spec

RuboCop::RakeTask.new(:rubocop)

desc "Lint Ruby and remote shell scripts"
task lint: :rubocop do
  scripts = ["bin/setup"] + Dir["script/**/*.sh"] + Dir["lib/kitsune/kit/scripts/**/*.sh"] +
            Dir["spec/fixtures/**/*.sh"]
  next if scripts.empty?

  shellcheck_available = system("shellcheck", "--version", out: File::NULL, err: File::NULL)
  abort "shellcheck is required to lint remote scripts" unless shellcheck_available

  sh "shellcheck", *scripts
end

desc "Install the built gem with freshly resolved dependencies and verify its public CLI"
task artifact_smoke: :build do
  artifact = "pkg/kitsune-kit-#{Kitsune::Kit::VERSION}.gem"
  abort "Built artifact is missing: #{artifact}" unless File.file?(artifact)

  sh "script/smoke-gem-artifact.sh", artifact
end

desc "Audit locked Ruby dependencies"
task :security do
  sh "bundle", "exec", "bundler-audit", "check", "--update"
end

desc "Run integration tests"
RSpec::Core::RakeTask.new(:integration) do |task|
  task.pattern = "spec/integration/**/*_spec.rb"
end
task :integration_environment do
  ENV["KITSUNE_INTEGRATION"] = "1"
  ENV["KITSUNE_COVERAGE_GATE"] = "0"
end
task integration: :integration_environment

desc "Run the real-provider end-to-end suite"
RSpec::Core::RakeTask.new(:e2e) do |task|
  abort "Set KITSUNE_E2E=1 to authorize ephemeral provider resources" unless ENV["KITSUNE_E2E"] == "1"

  task.pattern = "spec/e2e/**/*_spec.rb"
end
task :e2e_environment do
  ENV["KITSUNE_COVERAGE_GATE"] = "0"
end
task e2e: :e2e_environment

desc "Run the local pull-request checks"
task ci: %i[lint spec security build]

task default: :spec
