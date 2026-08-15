# frozen_string_literal: true

require "simplecov"

explicit_spec_files = ARGV.any? { |argument| argument.end_with?("_spec.rb") || argument.start_with?("spec/") }
coverage_gate = ENV.fetch("KITSUNE_COVERAGE_GATE", explicit_spec_files ? "0" : "1") == "1"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  minimum_coverage line: 80, branch: 50 if coverage_gate
end

require "kitsune/kit"
require "kitsune/kit/adapters/fake_provider"
require "kitsune/kit/adapters/fake_transport"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
    c.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed
end
