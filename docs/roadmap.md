# Roadmap and extension decisions

Kitsune Kit remains deliberately narrow until the complete DigitalOcean lifecycle is repeatedly green. This file
records decisions for the priority-4 items in the professionalization plan so “deferred” does not mean
“forgotten.”

## Hetzner evaluation

The current provider boundary is sufficiently generic for a second server adapter: credential validation,
server-spec validation, exact lookup/ID lifecycle, readiness and normalized `ServerRecord`. A Hetzner adapter
would need to map its locations, server types, images, SSH keys, status/IP representation, errors and deadlines
to that contract and pass the same fake/real lifecycle tests.

DNS must not be silently assumed equivalent to server provisioning. A future adapter must either implement the
existing exact-ID DNS contract through the selected Hetzner DNS product or declare DNS unsupported before
planning; provider conditionals must not leak into CLI/TUI code.

Decision: do not add Hetzner before the DigitalOcean E2E is reliably green and the adapter API has survived a
released 0.5.x version. When that gate is met, begin with a contract-only spike and an opt-in create/wait/resume/delete
test in an isolated account. This is an evaluated sequencing decision, not a claim of current support.

## External services

Implemented in schema version 1 through `services.TYPE.mode: external`. External endpoints are validated and
visible through `status`, but they produce no VPS operation. Kitsune Kit refuses install, backup, remove and
destroy-data because ownership remains with the service provider. This avoids assuming every database is a
local Compose service without pretending to provision arbitrary vendors.

Provider-specific database creation, TLS certificate distribution, database/user setup and backup APIs remain
out of scope until a concrete integration is selected and can have ownership/rollback semantics.

## Hooks and plugins

Decision: no arbitrary pre/post shell hooks or dynamic plugin loading before real use cases exist. Such a system
would enlarge the command-injection, secret and rollback surface while weakening plan accuracy. Small,
versioned ports remain the extension mechanism. A future hook proposal must define:

- a concrete use case that cannot be represented as an operation;
- typed inputs/outputs and secret annotations;
- whether it is observable during plan;
- timeout, idempotence, retry and cancellation behavior;
- ownership and rollback semantics;
- human/JSON/TUI event behavior;
- hostile-input, contract and E2E tests.

Until those requirements are met, no hook API is promised.
