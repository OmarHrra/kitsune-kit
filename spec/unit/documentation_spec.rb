# frozen_string_literal: true

require "spec_helper"
require "kitsune/kit/cli"
require "pathname"

RSpec.describe "project documentation" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:command_reference) { File.read(File.join(root, "docs/commands.md")) }
  let(:public_commands) do
    %w[apply dns docker doctor env help init plan resume rollback server service status support ui version]
  end

  it "ships every required documentation guide" do
    expected = %w[
      getting-started.md configuration.md commands.md security.md security-audit.md troubleshooting.md
      architecture.md testing.md tui.md roadmap.md providers/digitalocean.md
      services/postgres.md services/redis.md
    ]

    expect(expected).to all(satisfy { |path| File.file?(File.join(root, "docs", path)) })
  end

  it "exposes exactly the intentional public command surface" do
    expect(Kitsune::Kit::CLI.all_tasks.keys.sort).to eq(public_commands.sort)

    public_commands.each do |command|
      expect(command_reference).to include("kit #{command}")
    end
  end

  it "keeps the README sober and free of obsolete commands" do
    readme = File.read(File.join(root, "README.md"))

    expect(readme).not_to include("kit bootstrap", "setup_postgres_docker", "switch_env")
    expect(readme.scan(/[\u{1F300}-\u{1FAFF}]/)).to be_empty
    expect(readme).to include("Kitsune Kit is fully usable without the TUI")
  end

  it "keeps every relative Markdown link resolvable" do
    documents = Dir[File.join(root, "{README,CONTRIBUTING,SECURITY}.md")]
    documents.concat(Dir[File.join(root, "docs/**/*.md")])
    broken = documents.flat_map do |document|
      File.read(document).scan(/\[[^\]]+\]\(([^)]+)\)/).filter_map do |(target)|
        next if target.match?(%r{\A(?:https?://|mailto:|#)})

        relative = target.delete_prefix("<").delete_suffix(">").split("#", 2).first
        resolved = Pathname(File.dirname(document)).join(relative).cleanpath
        "#{document.delete_prefix("#{root}/")}: #{target}" unless resolved.exist?
      end
    end

    expect(broken).to be_empty, "Broken documentation links:\n#{broken.join("\n")}"
  end
end
