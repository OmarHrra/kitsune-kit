require "thor"
require "net/ssh"
require "fileutils"
require "shellwords"
require_relative "../defaults"
require_relative "../options_builder"
require "pry"
module Kitsune
  module Kit
    module Commands
      class SetupRedisDocker < Thor
        namespace "setup_redis_docker"

        class_option :server_ip, aliases: "-s", required: true, desc: "Server IP address or hostname"
        class_option :ssh_port, aliases: "-p", desc: "SSH port"
        class_option :ssh_key_path, aliases: "-k", desc: "Path to SSH private key"

        desc "create", "Setup Redis using Docker Compose on remote server"
        def create
          redis_defaults = Kitsune::Kit::Defaults.redis

          if redis_defaults[:redis_password] == "secret"
            say "⚠️ Warning: You are using the default Redis password ('secret').", :yellow
            if ENV.fetch("KIT_ENV", "development") == "production"
              abort "❌ Production environment requires a secure Redis password!"
            else
              say "🔒 Please change REDIS_PASSWORD in your .env if needed.", :yellow
            end
          end

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_setup(ssh, redis_defaults, filled_options)
          end
        end

        desc "rollback", "Remove Redis Docker setup from remote server"
        def rollback
          redis_defaults = Kitsune::Kit::Defaults.redis

          filled_options = Kitsune::Kit::OptionsBuilder.build(
            options,
            required: [:server_ip],
            defaults: Kitsune::Kit::Defaults.ssh
          )

          with_ssh_connection(filled_options) do |ssh|
            perform_rollback(ssh, redis_defaults)
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

          def perform_setup(ssh, redis_defaults, filled_options)
            local_compose = ".kitsune/docker/redis.yml"
            remote_dir = "$HOME/docker/redis"
            compose_remote = "#{remote_dir}/docker-compose.yml"
            env_remote = "#{remote_dir}/.env"
            marker = "/usr/local/backups/setup_redis_docker.after"

            abort "❌ Missing #{local_compose}" unless File.exist?(local_compose)

            # 1. Create base directory securely
            ssh.exec!("mkdir -p #{remote_dir} && chmod 700 #{remote_dir}")

            # 2. Upload docker-compose.yml
            say "📦 Uploading docker-compose.yml to #{remote_dir}", :cyan
            upload_file(ssh, File.read(local_compose), compose_remote)

            # 3. Create .env file for docker-compose based on redis_defaults
            env_content = <<~ENVFILE
              REDIS_PORT=#{redis_defaults[:redis_port]}
              REDIS_PASSWORD=#{redis_defaults[:redis_password]}
            ENVFILE
            upload_file(ssh, env_content, env_remote)

            # 4. Secure file permissions
            ssh.exec!("chmod 600 #{compose_remote} #{env_remote}")

            # 5. Create a backup marker
            ssh.exec!("sudo mkdir -p /usr/local/backups && sudo touch #{marker}")

            # 6. Validate docker-compose.yml
            say "🔍 Validating docker-compose.yml...", :cyan
            validation_output = ssh.exec!("cd #{remote_dir} && docker compose config")
            say validation_output, :cyan

            # 7. Check if container is running
            container_status = ssh.exec!("docker ps --filter 'name=redis' --format '{{.Status}}'").strip

            if container_status.empty?
              say "▶️ No running container. Running docker compose up...", :cyan
              ssh.exec!("cd #{remote_dir} && docker compose up -d")
            else
              say "⚠️ Redis container is already running.", :yellow
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

                redis = services.find { |svc| svc["Service"] == "redis" }
                status = redis && redis["State"]
                health = redis && redis["Health"]

                if (status == "running" && health == "healthy") || (health == "healthy")
                  say "✅ Redis container is running and healthy.", :green
                else
                  say "⚠️ Redis container is not healthy yet.", :yellow
                end
              rescue JSON::ParserError => e
                say "🚨 Failed to parse docker compose ps output as JSON: #{e.message}", :red
              end
            end

            # 9. Check Redis readiness with retries
            say "🔍 Checking Redis health with retries...", :cyan

            max_attempts = 10
            attempt = 0
            success = false

            while attempt < max_attempts
              attempt += 1
              healthcheck = ssh.exec!("docker exec $(docker ps -qf name=redis) redis-cli --no-auth-warning -a #{redis_defaults[:redis_password]} PING")

              if healthcheck.strip == "PONG"
                say "✅ Redis is up and responding to PING! (attempt #{attempt})", :green
                success = true

                redis_url = build_redis_url(filled_options, redis_defaults)
                say "🔗 Your REDIS_URL is:\t", :cyan
                say redis_url, :green
                break
              else
                say "⏳ Redis not ready yet, retrying in 5 seconds... (#{attempt}/#{max_attempts})", :yellow
                sleep 5
              end
            end

            unless success
              say "❌ Redis did not become ready after #{max_attempts} attempts.", :red
            end

            # 10. Allow Redis port through firewall (ufw)
            say "🛡️ Configuring firewall to allow Redis (port #{redis_defaults[:redis_port]})...", :cyan
            output = ssh.exec! <<~EOH
              if command -v ufw >/dev/null; then
                if ! sudo ufw status | grep -q "#{redis_defaults[:redis_port]}"; then
                  sudo ufw allow #{redis_defaults[:redis_port]}
                else
                  echo "💡 Port #{redis_defaults[:redis_port]} is already allowed in ufw."
                fi
              else
                echo "⚠️ ufw not found. Skipping firewall configuration."
              fi
            EOH
            say output

            say "✅ Redis setup completed successfully!", :green
          end

          def perform_rollback(ssh, defaults)
            output = ssh.exec! <<~EOH
              set -e
          
              BASE_DIR="$HOME/docker/redis"
              BACKUP_DIR="/usr/local/backups"
              SCRIPT_ID="setup_redis_docker"
              AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"
          
              if [ -f "$AFTER_FILE" ]; then
                echo "🔁 Stopping and removing docker containers..."
                cd "$BASE_DIR"
                docker compose down -v || true
          
                echo "🧹 Cleaning up files..."
                rm -rf "$BASE_DIR"
                sudo rm -f "$AFTER_FILE"
          
                if command -v ufw >/dev/null; then
                  echo "🛡️ Removing Redis port from firewall..."
                  sudo ufw delete allow #{defaults[:redis_port]} || true
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

          def build_redis_url(filled_options, redis_defaults)
            password = redis_defaults[:redis_password]
            host     = filled_options[:server_ip]
            port     = redis_defaults[:redis_port]
          
            "redis://:#{password}@#{host}:#{port}/0"
          end
        end
      end
    end
  end
end
