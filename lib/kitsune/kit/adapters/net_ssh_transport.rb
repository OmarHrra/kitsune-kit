# frozen_string_literal: true

require "base64"
require "net/ssh"
require "shellwords"
require "timeout"
require_relative "../errors"
require_relative "transport"

module Kitsune
  module Kit
    module Adapters
      class NetSshTransport < Transport
        def initialize(host:, user:, port:, key_path:, known_hosts: nil, verify_host_key: :always,
                       maximum_timeout: nil)
          super()
          @host = host
          @user = user
          @port = Integer(port)
          @key_path = key_path
          @known_hosts = known_hosts
          @verify_host_key = verify_host_key
          @maximum_timeout = maximum_timeout
        end

        def reachable?
          with_connection { true }
        rescue Errors::ConnectionError
          false
        end

        def with_session
          return yield if @persistent_session

          open_connection do |ssh|
            @persistent_session = ssh
            yield
          ensure
            @persistent_session = nil
          end
        end

        def execute(command, arguments: [], timeout: 30, stdin: nil)
          validate_command!(command)
          shell_command = ([command] + arguments.map { |argument| Shellwords.escape(argument.to_s) }).join(" ")
          started_at = monotonic_time
          stdout = +""
          stderr = +""
          exit_status = nil

          effective_timeout = @maximum_timeout ? [timeout, @maximum_timeout].min : timeout
          Timeout.timeout(effective_timeout) do
            with_connection do |ssh|
              ssh.open_channel do |channel|
                channel.exec(shell_command) do |_exec_channel, success|
                  raise Errors::RemoteCommandError, "remote command could not be started" unless success

                  channel.send_data(stdin) if stdin
                  channel.eof! if stdin
                  channel.on_data { |_data_channel, data| stdout << data }
                  channel.on_extended_data { |_data_channel, _type, data| stderr << data }
                  channel.on_request("exit-status") { |_status_channel, data| exit_status = data.read_long }
                end
              end
              ssh.loop
            end
          end

          command_result(stdout, stderr, exit_status, started_at)
        rescue Timeout::Error
          raise Errors::TimeoutError.new("remote command timed out after #{effective_timeout || timeout} seconds",
                                         context: { command: command })
        end

        def upload(content:, remote_path:, mode: "0600")
          validate_remote_path!(remote_path)
          validate_mode!(mode)
          encoded = Base64.strict_encode64(content)
          result = execute(
            "sh",
            arguments: ["-c", "base64 --decode > \"$1\" && chmod \"$2\" \"$1\"", "kitsune-upload", remote_path, mode],
            stdin: encoded,
            timeout: 30
          )
          raise_remote_failure!(result, "upload #{remote_path}") unless result.success?

          true
        end

        private

        def command_result(stdout, stderr, exit_status, started_at)
          CommandResult.new(
            stdout: stdout,
            stderr: stderr,
            exit_status: exit_status || 255,
            duration_ms: ((monotonic_time - started_at) * 1000).round
          )
        end

        def with_connection
          return yield(@persistent_session) if @persistent_session

          open_connection { |ssh| return yield(ssh) }
        end

        def open_connection
          options = {
            port: @port,
            keys: [@key_path],
            non_interactive: true,
            timeout: @maximum_timeout ? [10, @maximum_timeout].min : 10,
            verify_host_key: @verify_host_key
          }
          options[:user_known_hosts_file] = [@known_hosts] if @known_hosts
          Net::SSH.start(@host, @user, **options) { |ssh| return yield(ssh) }
        rescue Net::SSH::Exception, SystemCallError, SocketError => e
          raise Errors::ConnectionError.new(
            "SSH connection to #{@user}@#{@host}:#{@port} failed",
            hint: "Verify the address, key, host fingerprint and firewall rules.",
            context: { cause: e.class.name },
            retryable: true
          )
        end

        def validate_command!(command)
          return if command.to_s.match?(%r{\A[\w./-]+\z})

          raise Errors::ConfigurationError, "remote command has an invalid format"
        end

        def validate_remote_path!(path)
          return if path.to_s.match?(%r{\A/[a-zA-Z0-9_./-]+\z}) && !path.to_s.include?("..")

          raise Errors::ConfigurationError, "remote path has an invalid format"
        end

        def validate_mode!(mode)
          return if mode.to_s.match?(/\A0[0-7]{3}\z/)

          raise Errors::ConfigurationError, "file mode has an invalid format"
        end

        def raise_remote_failure!(result, operation)
          raise Errors::RemoteCommandError.new(
            "remote #{operation} failed with status #{result.exit_status}",
            context: { stderr: result.stderr }
          )
        end

        def monotonic_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
