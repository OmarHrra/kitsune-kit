# Changelog

All notable changes are documented here. The project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/); minor releases may change public interfaces before 1.0.

## [Unreleased]

## [0.6.0] - 2026-08-14

### Added

- Generated, overlay and fully custom Docker Compose modes for managed PostgreSQL and Redis.
- Local `compose show`, `validate`, `diff` and safe `eject` service commands.
- Project-bound file validation, inline-secret detection and explicit review metadata for unsafe Compose options.
- Multi-file upload, fingerprinting, state tracking, recovery and rollback for Compose customizations.
- Unit coverage for each customization mode, security boundary, ejection and remote multi-file execution.

### Changed

- Initialized projects now declare the generated Compose mode explicitly.
- Service state records the Compose mode, ordered file set and content fingerprint.
- Kitsune Kit 0.6.0 replaces the fixed service blueprints directly; no legacy blueprint compatibility layer remains.

### Security

- Customizations reject host namespace/device access, elevated capabilities, unmanaged ports, bind mounts, remote
  builds, unmanaged env files and inline secrets unless the documented explicit unsafe escape applies.

## [0.5.0] - 2026-08-14

### Added

- Comprehensive security hardening and release process.
- Architecture decisions for the direct rewrite, presentation parity, configuration, state and operation semantics.
- Contribution and security policies.
- Typed configuration, domain errors/results/events, versioned state, run journals and safe resume.
- Provider and SSH contracts with deterministic fakes and hardened DigitalOcean/Net::SSH adapters.
- Deterministic fake state/reporter adapters and shared real/fake state contracts.
- Read-only `doctor` and `plan`, non-interactive/JSON output, stable exit codes and support bundles.
- Ownership-aware server, DNS, Docker, PostgreSQL and Redis lifecycle operations.
- Optional pure-Ruby full-screen TUI over the same workflows as the conventional CLI.
- Unit, contract, hostile-input, CLI, headless TUI, Docker SSH integration and guarded DigitalOcean E2E suites.
- Matrix CI, dependency audit, shell lint, artifact installation smoke test, Dependabot and TTL resource cleanup.
- Complete user, security, provider, service, architecture, testing, troubleshooting and TUI documentation.
- Exact-ID server state import, schema compatibility guidance and a documented manual security audit.
- External PostgreSQL/Redis endpoint mode that never assumes or mutates a local Docker service.
- Pseudo-terminal TUI lifecycle and restoration coverage.

### Changed

- Version 0.5.0 directly replaces the earlier preview CLI; legacy compatibility is not a goal.
- Declare Ruby 3.2–3.4 support explicitly; Ruby 4 remains blocked by the current DigitalOcean SDK dependency chain.
- The command tree is now `init -> doctor -> plan -> apply`, with explicit resource subcommands.
- PostgreSQL and Redis are private and disabled by default; data destruction is separate from service removal.
- SSH, firewall, Docker and metrics setup use versioned verified scripts and captured rollback state.
- Safety-critical SSH/firewall transitions reuse a preserved session and transactionally recover failed changes.
- Service data destruction offers an optional backup and requires exact interactive or automation confirmation.

### Fixed

- Declared `base64`, `bigdecimal` and transitive `ostruct` requirements explicitly for supported Ruby releases.
- Made the ShellCheck availability probe portable across macOS and Ubuntu CI runners.
- Prevented framework commands added by newer Thor releases from silently changing Kitsune Kit's public CLI.
- Wait for SSH readiness after a new Droplet becomes active and reject mismatched E2E key pairs before billing.
- Validate DigitalOcean account access before E2E provisioning and avoid false server drift warnings.
- Use DropletKit's real `account.info` endpoint instead of a fake-only `account.get` method.
- Correct TUI plan/doctor shortcut routing and prevent full-width terminal frames from scrolling during redraws.
- Wait for authenticated SSH, rather than an open Docker proxy port, before running container integration cases.

### Removed

- Legacy bootstrap/setup command classes and interpolated Compose/env templates.
- The unused RBS placeholder; types will only return with a maintained, CI-checked contract.

### Security

- Added strict SSH host-key verification, input allow-lists, safe argument transport and secret redaction.
- Added exact provider/resource identity checks, atomic restricted state, protected Docker firewall rules and explicit destructive confirmations.
- Prevented Redis passwords from resolving into container command arguments and made installer/config temporaries failure-safe.

## [0.4.1] - 2025-06-01

### Fixed

- Corrected Redis defaults and removed an accidental debugger dependency from runtime code.

## [0.4.0] - 2025-05-04

### Added

- DigitalOcean DNS record management.

### Changed

- Replaced the external color dependency with the internal ANSI helper.
- Corrected generated development environment defaults.

## [0.3.0] - 2025-05-03

### Added

- Redis service setup with Docker Compose.
- Version command and initial CLI integration tests.

### Fixed

- Corrected SSH invocation and PostgreSQL setup behavior.

## [0.2.1] - 2025-05-01

### Changed

- Expanded documentation for swap and DigitalOcean metrics support.

## [0.2.0] - 2025-05-01

### Added

- Managed swap setup and rollback.
- DigitalOcean metrics-agent setup.

## [0.1.1] - 2025-05-01

### Added

- PostgreSQL firewall integration and improved CLI feedback.

## [0.1.0] - 2025-04-29

### Added

- First public preview.
- Bootstrap commands for DigitalOcean, Docker and PostgreSQL.

[Unreleased]: https://github.com/omarhrra/kitsune-kit/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/omarhrra/kitsune-kit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/omarhrra/kitsune-kit/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/omarhrra/kitsune-kit/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/omarhrra/kitsune-kit/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/omarhrra/kitsune-kit/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/omarhrra/kitsune-kit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/omarhrra/kitsune-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/omarhrra/kitsune-kit/releases/tag/v0.1.0
