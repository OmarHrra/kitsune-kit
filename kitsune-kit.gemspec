# frozen_string_literal: true

require_relative "lib/kitsune/kit/version"

Gem::Specification.new do |spec|
  spec.name = "kitsune-kit"
  spec.version = Kitsune::Kit::VERSION
  spec.authors = ["Omar Herrera"]
  spec.email = ["contact@omarherrera.me"]

  spec.summary = "Plan, provision, and configure secure Ubuntu servers for Docker and Kamal."
  spec.description = "Kitsune Kit is an inspectable infrastructure CLI for provisioning DigitalOcean servers, " \
                     "configuring Ubuntu and Docker, and managing private application services."
  spec.homepage = "https://github.com/omarhrra/kitsune-kit"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0", "< 4.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.txt",
    "README.md",
    "SECURITY.md",
    "bin/kit",
    "docs/**/*.md",
    "lib/**/*",
    "sig/**/*.rbs"
  ]
  spec.bindir = "bin"
  spec.executables = ["kit"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.3"
  spec.add_dependency "bcrypt_pbkdf", "~> 1.1"
  spec.add_dependency "bigdecimal", "~> 4.1"
  spec.add_dependency "droplet_kit", "~> 3.17"
  spec.add_dependency "ed25519", "~> 1.3"
  spec.add_dependency "net-ssh", "~> 7.2"
  spec.add_dependency "ostruct", "~> 0.6"
  spec.add_dependency "public_suffix", "~> 6.0"
  spec.add_dependency "thor", "~> 1.3"
end
