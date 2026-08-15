# frozen_string_literal: true

require_relative "../errors"

module Kitsune
  module Kit
    module Operations
      class ServiceBackup
        BACKUP_IMAGE = "alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc"

        def initialize(config:, type:, transport:, compose:, clock: -> { Time.now.utc })
          @config = config
          @type = type
          @transport = transport
          @compose = compose
          @clock = clock
        end

        def call(state)
          unless state&.fetch("installed", true)
            raise Errors::UnsafeOperationError.new(
              "#{type} is not installed",
              hint: "Install and verify the service before creating a data backup."
            )
          end

          directory = "/home/#{config.ssh.user}/.local/share/kitsune/backups/#{type}"
          path = "#{directory}/#{type}-#{clock.call.strftime('%Y%m%dT%H%M%S')}.tar.gz"
          create_directory(directory)
          create_archive(directory, path, state.fetch("volume"))
          path
        end

        private

        attr_reader :config, :type, :transport, :compose, :clock

        def create_directory(directory)
          result = transport.execute("mkdir", arguments: ["-p", directory], timeout: 10)
          raise_remote!(result, "create backup directory")
        end

        def create_archive(directory, path, volume)
          paused = false
          compose.call("pause")
          paused = true
          result = transport.execute(
            "docker",
            arguments: ["run", "--rm", "--volume", "#{volume}:/data:ro", "--volume", "#{directory}:/backup",
                        BACKUP_IMAGE, "tar", "-czf", "/backup/#{File.basename(path)}", "-C", "/data", "."],
            timeout: 600
          )
          raise_remote!(result, "back up service data")
          result = transport.execute("chmod", arguments: ["0600", path], timeout: 10)
          raise_remote!(result, "secure service backup")
        ensure
          compose.call("unpause") if paused
        end

        def raise_remote!(result, action)
          return if result.success?

          raise Errors::RemoteCommandError.new(
            "unable to #{action} for #{type}",
            context: { stderr: result.stderr, exit_status: result.exit_status }
          )
        end
      end
    end
  end
end
