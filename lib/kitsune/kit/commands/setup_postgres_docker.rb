require "thor"
require "net/ssh"
require "tempfile"
require "fileutils"
require "shellwords"
require_relative "../defaults"
require_relative "../options_builder"

module Kitsune
  module Kit
    module Commands
      class SetupPostgresDocker < Thor
        namespace "setup_postgres_docker"

        class_option :server_ip, aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port, aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "Path to SSH private key"

        desc "create", "Setup PostgreSQL using Docker Compose on remote server"
        def create
          postgres_defaults = Kitsune::Kit::Defaults.postgres

          if postgres_defaults[:postgres_password] == "secret"
            say "⚠️ Warning: You are using the default PostgreSQL password ('secret').", :yellow
            if ENV.fetch("KIT_ENV", "development") == "production"
              abort "❌ Production environment requires a secure PostgreSQL password!"
            else
              say "🔒 Please change POSTGRES_PASSWORD in your .env if needed.", :yellow
            end
          end

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_setup(ssh, postgres_defaults, filled_options)
          end
        end

        desc "rollback", "Remove PostgreSQL Docker setup from remote server"
        def rollback
          postgres_defaults = Kitsune::Kit::Defaults.postgres

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_rollback(ssh, postgres_defaults)
          end
        end

        no_commands do
          def with_ssh_connection(filled_options)
            server = filled_options[:server_ip]
            port   = filled_options[:ssh_port]
            key    = File.expand_path(filled_options[:ssh_key_path])

            say "🔑 Connecting as deploy@#{server}:#{port}", :green
            Net::SSH.start(server, "deploy", port: port, keys: [key], non_interactive: true, timeout: 5) do |ssh|
              yield ssh
            end
          end

          def perform_setup(ssh, postgres_defaults, filled_options)
            local_compose = ".kitsune/docker/postgres.yml"
            remote_dir = "$HOME/docker/postgres"
            compose_remote = "#{remote_dir}/docker-compose.yml"
            env_remote = "#{remote_dir}/.env"
            marker = "/usr/local/backups/setup_postgres_docker.after"

            abort "❌ Missing #{local_compose}" unless File.exist?(local_compose)

            # 1. Create base directory securely
            ssh.exec!("mkdir -p #{remote_dir} && chmod 700 #{remote_dir}")

            # 2. Upload docker-compose.yml
            say "📦 Uploading docker-compose.yml to #{remote_dir}", :cyan
            upload_file(ssh, File.read(local_compose), compose_remote)

            # 3. Create .env file for docker-compose based on postgres_defaults
            say "📦 Creating .env file for Docker Compose...", :cyan
            env_content = <<~ENVFILE
              POSTGRES_DB=#{postgres_defaults[:postgres_db]}
              POSTGRES_USER=#{postgres_defaults[:postgres_user]}
              POSTGRES_PASSWORD=#{postgres_defaults[:postgres_password]}
              POSTGRES_PORT=#{postgres_defaults[:postgres_port]}
              POSTGRES_IMAGE=#{postgres_defaults[:postgres_image]}
            ENVFILE
            upload_file(ssh, env_content, env_remote)

            # 4. Secure file permissions
            ssh.exec!("chmod 600 #{compose_remote} #{env_remote}")

            # 5. Create backup marker
            ssh.exec!("sudo mkdir -p /usr/local/backups && sudo touch #{marker}")

            # 6. Validate docker-compose.yml
            say "🔍 Validating docker-compose.yml...", :cyan
            validation_output = ssh.exec!("cd #{remote_dir} && docker compose config")
            say validation_output, :cyan

            # 7. Check if container is running
            container_status = ssh.exec!("docker ps --filter 'name=postgres' --format '{{.Status}}'").strip

            if container_status.empty?
              say "▶️ No running container. Running docker compose up...", :cyan
              ssh.exec!("cd #{remote_dir} && docker compose up -d")
            else
              say "⚠️ PostgreSQL container is already running.", :yellow
              if yes?("🔁 Recreate the container with updated configuration? [y/N]", :yellow)
                say "🔄 Recreating container...", :cyan
                ssh.exec!("cd #{remote_dir} && docker compose down -v && docker compose up -d")
              else
                say "⏩ Keeping existing container.", :cyan
              end
            end

            # 8. Check container status
            say "📋 Final container status (docker compose ps):", :cyan
            docker_ps_output = ssh.exec!("cd #{remote_dir} && docker compose ps --format json")

            if docker_ps_output.nil? || docker_ps_output.strip.empty? || docker_ps_output.include?("no configuration file")
              say "⚠️ docker compose ps returned no valid output.", :yellow
            else
              begin
                services = JSON.parse(docker_ps_output)
                services = [services] if services.is_a?(Hash)

                postgres = services.find { |svc| svc["Service"] == "postgres" }
                status = postgres && postgres["State"]
                health = postgres && postgres["Health"]

                if (status == "running" && health == "healthy") || (health == "healthy")
                  say "✅ PostgreSQL container is running and healthy.", :green
                else
                  say "⚠️ PostgreSQL container is not healthy yet.", :yellow
                end
              rescue JSON::ParserError => e
                say "🚨 Failed to parse docker compose ps output as JSON: #{e.message}", :red
              end
            end

            # 9. Check PostgreSQL readiness with retries
            say "🔍 Checking PostgreSQL health with retries...", :cyan

            max_attempts = 10
            attempt = 0
            success = false

            while attempt < max_attempts
              attempt += 1
              healthcheck = ssh.exec!("docker exec $(docker ps -qf name=postgres) pg_isready -U #{postgres_defaults[:postgres_user]} -d #{postgres_defaults[:postgres_db]} -h localhost")

              if healthcheck.include?("accepting connections")
                say "✅ PostgreSQL is up and accepting connections! (attempt #{attempt})", :green
                success = true

                database_url = build_database_url(filled_options, postgres_defaults)
                say "🔗 Your DATABASE_URL is:\t", :cyan
                say database_url, :green
                break
              else
                say "⏳ PostgreSQL not ready yet, retrying in 5 seconds... (#{attempt}/#{max_attempts})", :yellow
                sleep 5
              end
            end

            unless success
              say "❌ PostgreSQL did not become ready after #{max_attempts} attempts.", :red
            end

            # 10. Allow PostgreSQL port through firewall (ufw)
            say "🛡️ Configuring firewall to allow PostgreSQL (port #{postgres_defaults[:postgres_port]})...", :cyan
            output = ssh.exec! <<~EOH
              if command -v ufw >/dev/null; then
                if ! sudo ufw status | grep -q "#{postgres_defaults[:postgres_port]}"; then
                  sudo ufw allow #{postgres_defaults[:postgres_port]}
                else
                  echo "💡 Port #{postgres_defaults[:postgres_port]} is already allowed in ufw."
                fi
              else
                echo "⚠️ ufw not found. Skipping firewall configuration."
              fi
            EOH
            say output

            say "✅ PostgreSQL setup completed successfully!", :green
          end

          def perform_rollback(ssh, postgres_defaults)
            output = ssh.exec! <<~EOH
              set -e

              BASE_DIR="$HOME/docker/postgres"
              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_postgres_docker"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

              if [ -f "$AFTER_FILE" ]; then
                echo "🔁 Stopping and removing docker containers..."
                cd "$BASE_DIR"
                docker compose down -v || true

                echo "🧹 Cleaning up files..."
                rm -rf "$BASE_DIR"
                sudo rm -f "$AFTER_FILE"

                if command -v ufw >/dev/null; then
                  echo "🛡️ Removing PostgreSQL port from firewall..."
                  sudo ufw delete allow #{postgres_defaults[:postgres_port]} || true
                fi
              else
                echo "💡 Nothing to rollback"
              fi

              echo "✅ Rollback completed"
            EOH
            say output
          end

          def upload_file(ssh, content, remote_path)
            escaped = Shellwords.escape(content)
            ssh.exec!("mkdir -p #{File.dirname(remote_path)}")
            ssh.exec!("echo #{escaped} > #{remote_path}")
          end

          def build_database_url(filled_options, postgres_defaults)
            user = postgres_defaults[:postgres_user]
            password = postgres_defaults[:postgres_password]
            host = filled_options[:server_ip]
            port = postgres_defaults[:postgres_port]
            db = postgres_defaults[:postgres_db]

            "postgres://#{user}:#{password}@#{host}:#{port}/#{db}"
          end
        end
      end
    end
  end
end
