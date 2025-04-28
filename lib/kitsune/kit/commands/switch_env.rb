require "thor"
require "fileutils"

module Kitsune
  module Kit
    module Commands
      class SwitchEnv < Thor
        namespace "switch_env"

        desc "to ENV_NAME", "Switch active Kitsune Kit environment (development, production, etc)"
        def to(env_name)
          kit_env_path = ".kitsune/kit.env"
          infra_env_path = ".kitsune/infra.#{env_name}.env"
          blueprint_path = File.expand_path("../../blueprints/.env.template", __dir__)

          unless File.exist?(kit_env_path)
            say "❌ No .kitsune/kit.env found. Did you run `kitsune kit init`?", :red
            exit(1)
          end

          content = File.read(kit_env_path)

          if content.match?(/^KIT_ENV=/)
            new_content = content.gsub(/^KIT_ENV=.*/, "KIT_ENV=#{env_name}")
          else
            new_content = "KIT_ENV=#{env_name}\n" + content
          end

          File.write(kit_env_path, new_content)
          say "🎯 Environment switched to '#{env_name}' in .kitsune/kit.env", :green

          unless File.exist?(infra_env_path)
            FileUtils.cp(blueprint_path, infra_env_path)
            say "📝 Created new infra environment file: #{infra_env_path}", :cyan
          else
            say "📄 Infra environment file already exists: #{infra_env_path}", :green
          end
        end
      end
    end
  end
end
