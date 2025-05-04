# frozen_string_literal: true
ENV["KIT_ENV"] = "test"

require "kitsune/kit"

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

  config.before(:suite) do
    $original_stdout = $stdout
    $original_stderr = $stderr
    $stdout = File.open(File::NULL, "w")
    $stderr = File.open(File::NULL, "w")
  end

  config.after(:suite) do
    $stdout = $original_stdout
    $stderr = $original_stderr
  end
end
