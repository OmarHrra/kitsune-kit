# frozen_string_literal: true

require "spec_helper"

RSpec.describe "remote package management" do
  let(:scripts_directory) { File.expand_path("../../lib/kitsune/kit/scripts", __dir__) }
  let(:package_scripts) do
    Dir[File.join(scripts_directory, "*.sh")].select do |path|
      File.read(path).include?("apt-get")
    end
  end

  it "waits for dpkg locks and retries transient downloads in every package script" do
    expect(package_scripts).not_to be_empty

    package_scripts.each do |path|
      source = File.read(path)
      aggregate_failures(File.basename(path)) do
        expect(source).to include("DPkg::Lock::Timeout=120")
        expect(source).to include("Acquire::Retries=3")
        expect(source.scan(/\bapt-get\b/).size).to eq(1), "route every apt-get invocation through apt_get"
      end
    end
  end
end
