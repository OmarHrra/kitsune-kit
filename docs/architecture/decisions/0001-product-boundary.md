# ADR 0001: Product boundary and rewrite policy

- Status: accepted
- Date: 2026-08-14

## Context

The published preview has no known users or dependent projects. Its commands mix presentation, provider calls, SSH, shell scripts and state mutation. Preserving those interfaces would make unsafe behavior part of the new design.

## Decision

Kitsune Kit will manage the complete lifecycle of a small Ubuntu application server on DigitalOcean: provisioning, SSH policy, firewall, updates, swap, Docker, optional private PostgreSQL and Redis services, and DNS.

The existing CLI and configuration are not compatibility constraints. The new implementation replaces them directly. Git history is the archive for old behavior; production code will not contain legacy adapters or deprecated command aliases.

The rewrite may be released as 0.5.0 after its real-provider end-to-end suite passes reliably.

## Consequences

- Breaking changes are expected before 1.0.
- Documentation describes only the new interface.
- Each old implementation is deleted when its replacement is verified.
- Scope remains DigitalOcean and Ubuntu 22.04/24.04 until the first provider is stable.
