# ADR 0004: Supported platforms

- Status: accepted
- Date: 2026-08-14

## Decision

- Ruby 3.2 or newer is required.
- CI tests the oldest supported Ruby and current stable Ruby versions.
- Local clients support macOS and Linux.
- Managed servers support Ubuntu 22.04 and 24.04 LTS.
- Docker Compose v2 is required.
- DigitalOcean is the only supported provider before 1.0.

Ruby 3.2 is selected because the new core uses immutable `Data` value objects. Dependencies that require a newer patch or minor version must not be mandatory until the support declaration is updated and verified.
