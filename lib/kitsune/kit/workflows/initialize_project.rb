# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "../errors"

module Kitsune
  module Kit
    module Workflows
      class InitializeProject
        CONFIG = <<~YAML
          version: 1
          provider:
            name: digitalocean
            token_env: DO_API_TOKEN

          server:
            name: myapp-development
            region: sfo3
            size: s-1vcpu-1gb
            image: ubuntu-24-04-x64
            ssh_key_id: replace-with-digitalocean-key-id
            tags:
              - kitsune-managed

          ssh:
            user: deploy
            port: 22
            key_path: ~/.ssh/id_ed25519
            allowed_cidrs: []

          services:
            postgres:
              enabled: false
              mode: managed
              host:
              image: postgres:17
              publish: false
              bind: 127.0.0.1
              allowed_cidrs: []
              port: 5432
              password_env: POSTGRES_PASSWORD
              compose:
                mode: generated
                file:
                allow_unsafe: false
            redis:
              enabled: false
              mode: managed
              host:
              image: redis:7.2
              publish: false
              bind: 127.0.0.1
              allowed_cidrs: []
              port: 6379
              password_env: REDIS_PASSWORD
              compose:
                mode: generated
                file:
                allow_unsafe: false

          system:
            swap_size_gb: 2
            swap_swappiness: 10
            unattended_upgrades: true
            metrics: false
            metrics_installer_sha256:

          dns:
            domains: []
            ttl: 3600
        YAML

        ENVIRONMENT = <<~YAML
          version: 1
          server:
            name: myapp-development
        YAML

        def initialize(root: Dir.pwd)
          @root = Pathname(root).expand_path
        end

        def call(force: false)
          base = @root.join(".kitsune")
          files = {
            base.join("config.yml") => CONFIG,
            base.join("environments/development.yml") => ENVIRONMENT,
            base.join("environment") => "development\n"
          }
          existing = files.keys.select(&:exist?)
          if existing.any? && !force
            raise Errors::UnsafeOperationError.new(
              "Kitsune Kit configuration already exists",
              hint: "Use `kit init --force` only if replacing these files is intentional.",
              context: { files: existing.map(&:to_s) }
            )
          end

          files.each do |path, content|
            FileUtils.mkdir_p(path.dirname, mode: 0o700)
            path.write(content)
            File.chmod(0o600, path)
          end
          ensure_gitignore
          files.keys.map(&:to_s)
        end

        private

        def ensure_gitignore
          path = @root.join(".gitignore")
          lines = path.file? ? path.readlines(chomp: true) : []
          additions = [
            "/.kitsune/state/",
            "/.kitsune/logs/",
            "/.kitsune/support/",
            "/.kitsune/environment",
            "/.kitsune/known_hosts"
          ] - lines
          return if additions.empty?

          separator = lines.empty? || lines.last.empty? ? "" : "\n"
          File.open(path, "a", 0o644) { |file| file.write("#{separator}#{additions.join("\n")}\n") }
        end
      end
    end
  end
end
