# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tempfile"
require "spec_helper"

RSpec.describe "core coverage verifier" do
  it "uses the newest result instead of JSON insertion order" do
    results = {
      "newest" => result(timestamp: 20, branch_counts: [3, 1]),
      "older-but-last" => result(timestamp: 10, branch_counts: [0, 0])
    }

    Tempfile.create(["kitsune-coverage", ".json"]) do |file|
      file.write(JSON.generate(results))
      file.flush
      stdout, stderr, status = Open3.capture3(
        { "KITSUNE_COVERAGE_RESULT" => file.path, "KITSUNE_CORE_BRANCH_COVERAGE" => "100" },
        RbConfig.ruby, File.expand_path("../../script/verify-core-coverage", __dir__)
      )

      expect(status).to be_success
      expect(stderr).to be_empty
      expect(stdout).to include("100.00% (2/2)")
    end
  end

  def result(timestamp:, branch_counts:)
    {
      "timestamp" => timestamp,
      "coverage" => {
        File.expand_path("../../lib/kitsune/kit/example.rb", __dir__) => {
          "branches" => {
            "branch" => branch_counts.each_with_index.to_h { |count, index| ["arm-#{index}", count] }
          }
        }
      }
    }
  end
end
