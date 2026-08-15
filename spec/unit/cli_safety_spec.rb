# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "spec_helper"
require "kitsune/kit/cli"

RSpec.describe Kitsune::Kit::CLI do
  describe "support bundle review" do
    it "prints the redacted file contents and states that nothing was uploaded" do
      config = build_config
      app = Struct.new(:config, :provider, :state_store, :transport_factory, :operations)
                  .new(config, Object.new, Object.new, Object.new, [])
      cli = described_class.new([], { format: "human" }, {})
      path = File.join(Dir.mktmpdir("kitsune-support-cli"), "bundle.json")
      File.write(path, JSON.pretty_generate(schema_version: 1, token: "[REDACTED]") << "\n")
      workflow = instance_double(Kitsune::Kit::Workflows::SupportBundle, call: path)
      allow(cli).to receive(:build_application).and_return([app, nil])
      allow(Kitsune::Kit::Workflows::Doctor).to receive(:new).and_return(Object.new)
      allow(Kitsune::Kit::Workflows::SupportBundle).to receive(:new).and_return(workflow)

      expect { cli.support("bundle") }
        .to output(/Redacted contents.*\[REDACTED\].*did not upload/m).to_stdout
    ensure
      FileUtils.remove_entry(File.dirname(path)) if path && File.exist?(File.dirname(path))
    end
  end

  describe "external service boundaries" do
    it "reports the endpoint but refuses local lifecycle actions" do
      config = build_config(postgres: { enabled: true, mode: "external", host: "db.internal.example" })
      app = Struct.new(:config).new(config)
      cli = described_class.new([], { no_input: true }, {})

      expect(cli.send(:find_service_operation, app, "postgres", "status")).to be_nil
      expect { cli.send(:find_service_operation, app, "postgres", "install") }
        .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /external service/)
      expect { cli.send(:service_status, app, "postgres") }
        .to output(/external \(db\.internal\.example:5432\)/).to_stdout
    end
  end

  describe "service data destruction" do
    let(:config) { build_config }
    let(:state_store) { Kitsune::Kit::Adapters::FakeStateStore.new }
    let(:app) do
      Struct.new(:config, :state_store).new(config, state_store)
    end
    let(:operation) { instance_double(Kitsune::Kit::Operations::EnsureService) }

    before do
      state_store.update(config.environment) do |state|
        state["resources"]["service.postgres"] = {
          "managed" => true, "installed" => true, "volume" => "kitsune-production-postgres_data"
        }
        state
      end
    end

    it "creates an explicitly requested backup before exact non-interactive destruction" do
      cli = described_class.new(
        [], { no_input: true, backup_before_destroy: true, confirm_destroy: "postgres@test" }, {}
      )
      allow(cli).to receive(:print_destructive_summary)
      expect(operation).to receive(:backup).ordered.and_return("/remote/postgres.tar.gz")
      expect(operation).to receive(:destroy_data).ordered.and_return(true)

      result = cli.send(:destroy_service_data, app, operation, "postgres")

      expect(result.value).to eq(destroyed: true, backup: "/remote/postgres.tar.gz")
    end

    it "does not destroy data when the exact automation confirmation is absent" do
      cli = described_class.new([], { no_input: true, backup_before_destroy: false }, {})
      allow(cli).to receive(:print_destructive_summary)
      expect(operation).not_to receive(:backup)
      expect(operation).not_to receive(:destroy_data)

      expect { cli.send(:destroy_service_data, app, operation, "postgres") }
        .to raise_error(Kitsune::Kit::Errors::UnsafeOperationError, /not confirmed/)
    end
  end
end
