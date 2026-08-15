# ADR 0007: Managed Compose customization boundary

- Status: accepted
- Date: 2026-08-14

## Context

The fixed PostgreSQL and Redis generators are safe and convenient, but cannot express every operational Docker
setting. Making arbitrary YAML fragments part of the core configuration would duplicate the Compose schema and
produce a weaker, less familiar interface.

## Decision

Managed services support three explicit modes: deterministic generated output, a generated base plus one project
overlay, and one complete project-owned custom document. All modes pass through a single renderer, fingerprint,
remote validation, state and recovery path.

Customization files remain within the project and are subject to size, type, secret and host-boundary validation.
Security-sensitive Compose settings fail closed unless `allow_unsafe` records an explicit operator decision.
Inline secrets always fail. The `eject` command creates a complete custom starting point and a configuration
backup instead of preserving compatibility with the earlier fixed blueprint internals.

## Consequences

- Users can express ordinary Compose settings without Kitsune Kit reimplementing the Compose schema.
- Generated mode remains the default and safest supported path.
- Custom mode transfers responsibility for image, health, network and volume semantics to the project.
- Kitsune Kit tracks and restores the ordered document set, but does not claim ownership of arbitrary host
  resources introduced through the unsafe escape hatch.
- Docker's server-side `compose config` remains authoritative for Compose-version compatibility.
