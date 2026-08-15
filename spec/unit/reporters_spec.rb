# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"

RSpec.describe "event reporters" do
  let(:event) do
    Kitsune::Kit::Events::Event.build(
      "warning_emitted",
      run_id: "run-1",
      message: "token is super-secret",
      token: "super-secret"
    )
  end

  it "renders readable, secret-free human output" do
    output = StringIO.new
    reporter = Kitsune::Kit::Reporters::Human.new(
      output: output,
      error: output,
      color: false,
      secret_filter: Kitsune::Kit::SecretFilter.new(["super-secret"])
    )

    reporter.handle(event)

    expect(output.string).to include("[WARN]", "[REDACTED]")
    expect(output.string).not_to include("super-secret")
  end

  it "emits one valid, versioned JSON document" do
    output = StringIO.new
    reporter = Kitsune::Kit::Reporters::Json.new(
      output: output,
      secret_filter: Kitsune::Kit::SecretFilter.new(["super-secret"])
    )
    reporter.handle(Kitsune::Kit::Events::Event.build(
                      "run_started", run_id: "run-1", command: "doctor", environment: "production"
                    ))
    reporter.handle(event)
    reporter.handle(Kitsune::Kit::Events::Event.build(
                      "run_finished", run_id: "run-1", status: "success", duration_ms: 42
                    ))
    reporter.flush(result: Kitsune::Kit::Result.success("ok"))

    payload = JSON.parse(output.string)
    expect(payload).to include(
      "schema_version" => 1,
      "command" => "doctor",
      "environment" => "production",
      "run_id" => "run-1",
      "status" => "success",
      "duration_ms" => 42,
      "result" => "ok"
    )
    expect(output.string).not_to include("super-secret")
  end

  it "uses the latest workflow metadata when one invocation plans and then applies" do
    output = StringIO.new
    reporter = Kitsune::Kit::Reporters::Json.new(output: output)
    reporter.handle(
      Kitsune::Kit::Events::Event.build("run_started", run_id: "plan", command: "plan", environment: "test")
    )
    reporter.handle(
      Kitsune::Kit::Events::Event.build("run_finished", run_id: "plan", status: "success", duration_ms: 1)
    )
    reporter.handle(
      Kitsune::Kit::Events::Event.build("run_started", run_id: "apply", command: "apply", environment: "test")
    )
    reporter.handle(
      Kitsune::Kit::Events::Event.build("run_finished", run_id: "apply", status: "success", duration_ms: 2)
    )

    payload = reporter.flush(result: Kitsune::Kit::Result.success, command: "apply")
    expect(payload).to include(command: "apply", run_id: "apply", duration_ms: 2)
  end

  it "accepts explicit command environment metadata for event-free actions" do
    output = StringIO.new
    reporter = Kitsune::Kit::Reporters::Json.new(output: output)

    payload = reporter.flush(
      result: Kitsune::Kit::Result.success(["development"]),
      command: "env.list",
      environment: "development"
    )

    expect(payload).to include(
      schema_version: 1, command: "env.list", environment: "development", status: "success",
      result: ["development"], events: []
    )
  end
end
