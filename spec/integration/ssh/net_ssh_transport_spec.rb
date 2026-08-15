# frozen_string_literal: true

require "open3"
require "securerandom"
require "spec_helper"

RSpec.describe "Net::SSH transport against an ephemeral sshd", :integration do
  def command!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{command.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end

  def docker_available?
    system("docker", "info", out: File::NULL, err: File::NULL)
  end

  before(:all) do
    skip "Docker is unavailable; run this suite on a Docker-enabled host" unless docker_available?

    @temporary_directory = Dir.mktmpdir("kitsune-ssh-integration")
    @key_path = File.join(@temporary_directory, "id_ed25519")
    command!("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", @key_path)
    public_key = File.read("#{@key_path}.pub").strip
    ubuntu = ENV.fetch("KITSUNE_TEST_UBUNTU", "24.04")
    @image = "kitsune-ssh-test:#{ubuntu.tr('.', '-')}-#{SecureRandom.hex(4)}"
    fixture = File.expand_path("../../fixtures/ssh", __dir__)
    command!("docker", "build", "--build-arg", "UBUNTU_VERSION=#{ubuntu}", "--tag", @image, fixture)
    @container = command!(
      "docker", "run", "--detach", "--publish", "127.0.0.1::22",
      "--env", "AUTHORIZED_KEY=#{public_key}", @image
    )
    published = command!("docker", "port", @container, "22/tcp")
    @port = Integer(published.split(":").last)
    wait_for_authenticated_ssh!
  end

  after do |example|
    next unless example.exception && @container && !@diagnostics_printed

    stdout, stderr, = Open3.capture3("docker", "logs", @container)
    warn "\nEphemeral sshd container logs:\n#{stdout}#{stderr}"
    @diagnostics_printed = true
  end

  after(:all) do
    system("docker", "rm", "--force", @container, out: File::NULL, err: File::NULL) if @container
    system("docker", "image", "rm", "--force", @image, out: File::NULL, err: File::NULL) if @image
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory && File.directory?(@temporary_directory)
  end

  def transport(key_path: @key_path, verifier: :never, maximum_timeout: nil)
    Kitsune::Kit::Adapters::NetSshTransport.new(
      host: "127.0.0.1", user: "root", port: @port, key_path: key_path,
      verify_host_key: verifier, maximum_timeout: maximum_timeout
    )
  end

  def wait_for_authenticated_ssh!
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    last_error = nil

    loop do
      return if transport(maximum_timeout: 2).execute("true", timeout: 2).success?
    rescue Kitsune::Kit::Errors::ConnectionError => e
      last_error = e
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.2
    end

    stdout, stderr, = Open3.capture3("docker", "logs", @container)
    raise "ephemeral sshd did not accept authenticated SSH: #{last_error&.message}\n#{stdout}#{stderr}"
  end

  it "authenticates, preserves output channels and quotes hostile arguments" do
    value = "space ; $(touch /tmp/kitsune-owned)"
    result = transport.execute("printf", arguments: ["%s", value])

    expect(result.stdout).to eq(value)
    expect(result.stderr).to eq("")
    expect(result.exit_status).to eq(0)
    expect(transport.execute("test", arguments: ["!", "-e", "/tmp/kitsune-owned"])).to be_success
  end

  it "uploads exact bytes with restrictive permissions" do
    payload = "line one\n$(id)\n"
    expect(transport.upload(content: payload, remote_path: "/tmp/kitsune-upload", mode: "0600")).to be(true)

    expect(transport.execute("cat", arguments: ["/tmp/kitsune-upload"]).stdout).to eq(payload)
    expect(transport.execute("stat", arguments: ["-c", "%a", "/tmp/kitsune-upload"]).stdout.strip).to eq("600")
  end

  it "rejects an untrusted host key and a wrong authentication key" do
    expect { transport(verifier: :always).execute("true") }
      .to raise_error(Kitsune::Kit::Errors::ConnectionError)

    wrong_key = File.join(@temporary_directory, "wrong_ed25519")
    command!("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", wrong_key)
    expect { transport(key_path: wrong_key).execute("true") }
      .to raise_error(Kitsune::Kit::Errors::ConnectionError)
  end

  it "enforces a real remote-command timeout" do
    expect { transport(maximum_timeout: 0.1).execute("sleep", arguments: ["2"], timeout: 5) }
      .to raise_error(Kitsune::Kit::Errors::TimeoutError)
  end

  it "keeps one authenticated session usable across a verified multi-step transition" do
    current = transport
    results = current.with_session do
      [current.execute("printf", arguments: ["first"]), current.execute("printf", arguments: ["second"])]
    end

    expect(results.map(&:stdout)).to eq(%w[first second])
  end
end
