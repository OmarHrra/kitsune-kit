# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "versioned remote scripts", :integration do
  let(:scripts) { Dir[File.expand_path("../../../lib/kitsune/kit/scripts/*.sh", __dir__)].sort }

  it "parses with Bash on the selected supported Ubuntu image" do
    skip "Docker is unavailable; run this suite on a Docker-enabled host" unless system(
      "docker", "info", out: File::NULL, err: File::NULL
    )

    ubuntu = ENV.fetch("KITSUNE_TEST_UBUNTU", "24.04")
    scripts.each do |script|
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm", "--volume", "#{script}:/script.sh:ro",
        "ubuntu:#{ubuntu}", "bash", "-n", "/script.sh"
      )
      expect(status).to be_success, "#{File.basename(script)}: #{stdout}#{stderr}"
    end
  end
end
