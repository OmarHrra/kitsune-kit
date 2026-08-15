# frozen_string_literal: true

RSpec.shared_examples "a transport adapter" do
  it "reports reachability" do
    expect(transport.reachable?).to be(true)
    expect(unreachable_transport.reachable?).to be(false)
  end

  it "maps an exhausted command deadline to the timeout contract" do
    expect { timeout_transport.execute("true", timeout: 1) }
      .to raise_error(Kitsune::Kit::Errors::TimeoutError)
  end

  it "returns stdout, stderr, status and duration separately" do
    result = transport.execute("printf", arguments: ["safe-value"])

    expect(result).to be_success
    expect(result.stdout).to eq("safe-value")
    expect(result.stderr).to eq("")
    expect(result.duration_ms).to be_a(Integer)
  end

  it "uploads content with an explicit mode" do
    expect(transport.upload(content: "secret", remote_path: "/tmp/contract", mode: "0600")).to be(true)
  end

  it "supports a scoped session for multi-step verified transitions" do
    result = transport.with_session { transport.execute("printf", arguments: ["safe-value"]) }

    expect(result.stdout).to eq("safe-value")
  end
end
