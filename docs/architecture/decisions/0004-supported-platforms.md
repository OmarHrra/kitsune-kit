# ADR 0004: Supported platforms

- Status: accepted
- Date: 2026-08-14

## Decision

- Ruby 3.2, 3.3 and 3.4 are supported (`>= 3.2`, `< 4.0`).
- CI tests every supported Ruby minor version.
- Local clients support macOS and Linux.
- Managed servers support Ubuntu 22.04 and 24.04 LTS.
- Docker Compose v2 is required.
- DigitalOcean is the only supported provider before 1.0.

Ruby 3.2 is selected because the new core uses immutable `Data` value objects. Dependencies that require a newer patch or minor version must not be mandatory until the support declaration is updated and verified.

Ruby 4 is excluded from the 0.5.0 contract because DropletKit 3.22 constrains `faraday-retry` to the 2.2 series,
whose gem metadata requires Ruby `< 4`. Support can be enabled once that provider dependency accepts a
Ruby-4-compatible `faraday-retry` release, or when the provider adapter no longer depends on that SDK.
