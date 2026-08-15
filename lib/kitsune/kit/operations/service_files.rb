# frozen_string_literal: true

require_relative "../errors"

module Kitsune
  module Kit
    module Operations
      class ServiceFiles
        def initialize(config:, type:, transport:, state_store:, resource:, fingerprint:, compose_filenames:)
          @config = config
          @type = type
          @transport = transport
          @state_store = state_store
          @resource = resource
          @fingerprint = fingerprint
          @compose_filenames = compose_filenames
        end

        def directory = "/home/#{config.ssh.user}/.local/share/kitsune/services/#{type}"
        def compose_path(filename = "compose.yml") = "#{directory}/#{filename}"
        def compose_paths = compose_filenames.call.map { |filename| compose_path(filename) }
        def env_path = "#{directory}/.env"
        def backup_directory = "/var/lib/kitsune/backups/service-#{type}-#{fingerprint.call[0, 12]}"

        def ensure_managed_or_absent!(actual_fingerprint)
          return if managed?
          return if actual_fingerprint.empty? && known_paths.none? { |path| exists?(path) }

          raise Errors::UnsafeOperationError.new(
            "refusing to replace unmanaged #{type} service files",
            hint: "Restore the local state backup or move the existing files before applying again.",
            context: { directory: directory }
          )
        end

        def prepare_backup
          result = transport.execute(
            "sudo",
            arguments: ["install", "-d", "-m", "0700", "-o", config.ssh.user, "-g", config.ssh.user,
                        backup_directory],
            timeout: 20
          )
          raise_remote!(result, "create service backup directory")
          known_paths.select { |path| exists?(path) }.tap do |paths|
            paths.each { |path| copy(path, backup_directory) }
          end
        end

        def restore_after_failure(backed_up_files)
          transport.execute("rm", arguments: ["-f", *known_paths], timeout: 20)
          backed_up_files.each { |path| copy("#{backup_directory}/#{File.basename(path)}", File.dirname(path)) }
        end

        def restore_previous(previous, marker_path:)
          if previous["backup_directory"]
            restore_files(previous["backup_directory"], previous.fetch("backed_up_files", []))
            restore_marker(marker_path, previous["previous_fingerprint"])
            remove_backup(previous["backup_directory"])
            true
          else
            transport.execute("rm", arguments: ["-rf", directory], timeout: 30)
            transport.execute("sudo", arguments: ["rm", "-f", marker_path], timeout: 10)
            false
          end
        end

        def destroy(entry, marker_path:)
          result = transport.execute("rm", arguments: ["-rf", directory], timeout: 30)
          raise_remote!(result, "remove service files")
          result = transport.execute("sudo", arguments: ["rm", "-f", marker_path], timeout: 10)
          raise_remote!(result, "remove service marker")
          backup_directories(entry).each { |backup| remove_backup(backup) }
        end

        private

        attr_reader :config, :type, :transport, :state_store, :resource, :fingerprint, :compose_filenames

        def known_paths
          previous = state_store.read(config.environment).dig("resources", resource, "compose_files") || []
          (compose_paths + previous.map { |filename| compose_path(filename) } + [env_path]).uniq
        end

        def managed? = !!state_store.read(config.environment).dig("resources", resource, "managed")
        def exists?(path) = transport.execute("test", arguments: ["-e", path], timeout: 10).success?

        def restore_files(directory, files)
          files.each { |path| copy("#{directory}/#{File.basename(path)}", File.dirname(path)) }
        end

        def copy(source, destination)
          result = transport.execute(
            "cp", arguments: ["--preserve=mode,ownership", source, destination], timeout: 20
          )
          raise_remote!(result, "copy service files")
        end

        def restore_marker(path, value)
          return transport.execute("sudo", arguments: ["rm", "-f", path], timeout: 10) unless value

          result = transport.execute("sudo", arguments: ["tee", path], stdin: "#{value}\n", timeout: 10)
          raise_remote!(result, "restore service marker")
        end

        def remove_backup(directory)
          result = transport.execute("sudo", arguments: ["rm", "-rf", directory], timeout: 30)
          raise_remote!(result, "remove restored service backup")
        end

        def backup_directories(entry)
          current = entry
          [].tap do |directories|
            while current
              directories << current["backup_directory"] if current["backup_directory"]
              current = current["previous_state"]
            end
          end.uniq
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
