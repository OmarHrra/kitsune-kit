# frozen_string_literal: true

require "stringio"
require "spec_helper"
load File.expand_path("../../script/cleanup-ci-resources", __dir__)

RSpec.describe CleanupCiResources do
  let(:record_class) { Data.define(:id, :name, :tags) }
  let(:droplets_api) do
    Class.new do
      attr_reader :deleted, :query

      def initialize(records)
        @records = records
        @deleted = []
      end

      def all(tag_name:)
        @query = tag_name
        @records.select { |record| record.tags.include?(tag_name) }
      end

      def delete(id:)
        @deleted << id
      end
    end.new(records)
  end
  let(:client) { Struct.new(:droplets).new(droplets_api) }
  let(:output) { StringIO.new }
  let(:records) do
    [
      record_class.new(id: 1, name: "expired", tags: %w[kitsune-ci kitsune-expires-100]),
      record_class.new(id: 2, name: "future", tags: %w[kitsune-ci kitsune-expires-300]),
      record_class.new(id: 3, name: "untagged", tags: %w[kitsune-expires-100]),
      record_class.new(id: 4, name: "invalid", tags: %w[kitsune-ci kitsune-expires-never])
    ]
  end

  it "dry-runs only expired, exactly tagged CI droplets" do
    result = described_class.new(client: client, now: 200, output: output).call

    expect(result.map(&:id)).to eq([1])
    expect(droplets_api.query).to eq("kitsune-ci")
    expect(droplets_api.deleted).to be_empty
    expect(output.string).to include("Would delete expired CI droplet 1", "Dry run only")
  end

  it "deletes only the filtered IDs when execution is explicit" do
    described_class.new(client: client, now: 200, output: output).call(execute: true)

    expect(droplets_api.deleted).to eq([1])
    expect(output.string).to include("Deleted expired CI droplet 1")
    expect(output.string).not_to include("Dry run only")
  end
end
