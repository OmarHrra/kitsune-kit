require "thor"
require "fileutils"

module Kitsune
  module Kit
    module Commands
      class Init < Thor
        namespace "init"

        default_task :init

        desc "init", "Initialize Kitsune Kit project structure"
        def init
          say "✨ Initializing Kitsune project...", :green
          create_base_structure
          selected_envs = select_environments
          copy_env_templates(selected_envs)
          selected_default_env = select_default_environment(selected_envs)
          create_kit_env(selected_default_env)
          copy_docker_templates
          say "🎉 Done! '.kitsune/' structure is ready.", :green
        end

        no_commands do
          def blueprint_path(relative_path)
            File.expand_path("../../blueprints/#{relative_path}", __dir__)
          end

          def create_base_structure
            dirs = [
              ".kitsune",
              ".kitsune/docker"
            ]
            dirs.each do |dir|
              unless Dir.exist?(dir)
                FileUtils.mkdir_p(dir)
                say "📂 Created directory: #{dir}", :cyan
              else
                say "📂 Directory already exists: #{dir}", :yellow
              end
            end
          end

          def environments_options
            {
              "1" => "development",
              "2" => "production",
              "3" => "staging",
              "4" => "test"
            }
          end

          def select_environments
            say "🌎 Which environments do you want to create?", :cyan
            environments_options.each do |number, env|
              say "  #{number}) #{env}"
            end
            input = ask("➡️  Enter numbers separated by commas (or type 'all') [default: all]:", :yellow)
            input = input.strip.downcase

            if input.empty? || input == "all"
              environments_options.values
            else
              selected = input.split(",").map(&:strip)
              environments = selected.map { |num| environments_options[num] }.compact
              if environments.empty?
                say "⚠️ Invalid selection. Creating all environments.", :yellow
                environments_options.values
              else
                environments
              end
            end
          end

          def select_default_environment(selected_envs)
            say "🎯 Which environment should be set as default in '.kitsune/kit.env'?", :cyan
            selected_envs.each_with_index do |env, index|
              say "  #{index + 1}) #{env}"
            end
            input = ask("➡️  Enter number [default: 1]:", :yellow)
            input = input.strip

            if input.empty?
              selected_envs[0] # default to first selected
            else
              index = input.to_i - 1
              if index >= 0 && index < selected_envs.size
                selected_envs[index]
              else
                say "⚠️ Invalid selection. Defaulting to '#{selected_envs[0]}'", :yellow
                selected_envs[0]
              end
            end
          end

          def create_kit_env(default_env)
            path = ".kitsune/kit.env"
            template = File.read(blueprint_path("kit.env.template"))
            content = template.gsub("KIT_ENV=development", "KIT_ENV=#{default_env}")
          
            if File.exist?(path)
              if yes?("⚠️  File #{path} already exists. Overwrite? [y/N]", :yellow)
                File.write(path, content)
                say "✅ Overwritten: #{path}", :cyan
              else
                say "⏩ Skipped: #{path}", :yellow
              end
            else
              File.write(path, content)
              say "📝 Created: #{path}", :cyan
            end

            say ""
            say "🎯 Kitsune Kit environment set to: #{default_env}", :green
            say "📄 Environment file used: .kitsune/infra.#{default_env}.env", :green
            say ""
          end

          def copy_env_templates(selected_envs)
            selected_envs.each do |env|
              dest_path = ".kitsune/infra.#{env}.env"
              copy_with_prompt(blueprint_path(".env.template"), dest_path)
            end
          end

          def copy_docker_templates
            copy_with_prompt(blueprint_path("docker/postgres.yml"), ".kitsune/docker/postgres.yml")
            copy_with_prompt(blueprint_path("docker/redis.yml"), ".kitsune/docker/redis.yml")
          end

          def copy_with_prompt(source, destination)
            if File.exist?(destination)
              if yes?("⚠️  File #{destination} already exists. Overwrite? [y/N]", :yellow)
                FileUtils.cp(source, destination)
                say "✅ Overwritten: #{destination}", :cyan
              else
                say "⏩ Skipped: #{destination}", :yellow
              end
            else
              FileUtils.cp(source, destination)
              say "📝 Created: #{destination}", :cyan
            end
          end
        end
      end
    end
  end
end
