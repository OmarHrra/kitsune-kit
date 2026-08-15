# Contributing to Kitsune Kit

Kitsune Kit is being rebuilt as a secure, inspectable infrastructure CLI. Read the architecture decisions in `docs/architecture/decisions` before changing public commands, configuration, state, events or destructive behavior.

## Setup

Requirements:

- Ruby 3.2 or newer
- Bundler 4.0.18
- ShellCheck for remote script linting
- Docker for integration tests

Run:

```bash
bin/setup
bundle exec rake ci
```

## Development commands

```bash
bundle exec rake spec       # Ruby tests
bundle exec rake lint       # Ruby and shell lint
bundle exec rake security   # dependency audit
bundle exec rake build      # build the gem
bundle exec rake artifact_smoke # install the gem with fresh dependencies and verify its CLI
bundle exec rake ci         # local pull-request gate
```

Integration and real-provider tests are kept separate because they require Docker or credentials:

```bash
bundle exec rake integration
KITSUNE_E2E=1 bundle exec rake e2e
```

## Adding an operation

An operation must validate input, calculate a non-mutating plan, be idempotent, verify its result, declare destructive effects, redact secrets, use timeouts and have success/no-change/failure tests. Provider and SSH code belongs in adapters, not workflows or presentation classes.

Every action exposed in the TUI must have a CLI equivalent. Domain behavior is tested below either presentation layer.

## Adding or changing a provider

Implement the provider port without leaking SDK values or exceptions into the core. The adapter must:

- use exact provider IDs for destructive calls;
- preserve configured ownership tags;
- map authentication, retryable provider and timeout failures to domain errors;
- persist an ID before waiting on a newly created resource;
- satisfy the shared provider contract and adapter-specific HTTP/SDK tests;
- document credentials, permissions, identity and cleanup behavior.

Do not add a second provider until its full create/wait/resume/delete lifecycle can run through existing workflows without provider conditionals in presentation code.

## Tests

Every behavior change needs the smallest appropriate unit/contract tests plus integration coverage when it crosses a real process, SSH or shell boundary. Destructive paths, failure-after-mutation, retry/resume, timeout and hostile inputs require explicit examples.

Run the complete local gate before opening a pull request:

```bash
bundle exec rake ci
bundle exec rake integration # when Docker/SSH/scripts changed
```

The DigitalOcean E2E suite is billable and credential-gated. Never run it against a production account; follow `docs/testing.md`.

## Pull requests

- Keep changes focused on one coherent capability.
- Include tests and documentation with behavior changes.
- Never commit tokens, private keys, `.kitsune/state`, logs or generated support bundles.
- Explain destructive behavior and rollback semantics explicitly.
- Update `CHANGELOG.md` under `Unreleased` for user-visible changes.

Commit messages should be imperative and describe one coherent change. Pull requests should explain user-visible behavior, security/destruction implications, test evidence and any migration. A maintainer may squash on merge.

## Releases

Releases follow `docs/releasing.md`. Do not publish manually with a long-lived RubyGems API key. The protected `release` environment and RubyGems trusted publisher must approve the tag-triggered workflow.
