# frozen_string_literal: true

require_relative "lib/kitsune/kit/version"

Gem::Specification.new do |spec|
  spec.name = "kitsune-kit"
  spec.version = Kitsune::Kit::VERSION
  spec.authors = ["Omar Herrera"]
  spec.email = ["contact@omarherrera.me"]

  spec.summary = "Provision and setup DigitalOcean VPSs with Docker and PostgreSQL, ideal for Kamal deployments."
  spec.description = "Kitsune Kit is a CLI toolkit that automates the provisioning, configuration, and Docker setup of remote servers, especially tailored for Ruby developers using Kamal. Includes rollback features and multi-environment support."
  spec.homepage = "https://github.com/omarhrra/kitsune-kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["kit"]
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "net-ssh"
  spec.add_dependency "ed25519"
  spec.add_dependency "bcrypt_pbkdf"
  spec.add_dependency "dotenv"
  spec.add_dependency "droplet_kit"
  spec.add_dependency "thor"
  spec.add_development_dependency "pry"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
