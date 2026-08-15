# Release process

Kitsune Kit follows Semantic Versioning. Before 1.0, minor releases may make incompatible changes, but every schema or command change must be documented in `CHANGELOG.md`.

## One-time repository setup

1. Protect `main` and version tags; require the CI jobs.
2. Create a GitHub environment named `release` with required reviewers.
3. Configure `release.yml` as a trusted publisher for `kitsune-kit` on RubyGems.org, scoped to the `release` environment.
4. Require MFA for gem owners and protect GitHub accounts with strong MFA.
5. Configure the separate DigitalOcean E2E secrets/account and budget alerts.

The workflow uses OIDC short-lived credentials through `rubygems/release-gem`; no `GEM_HOST_API_KEY` secret is stored.

## Release checklist

1. Ensure normal CI is green on every supported Ruby and Ubuntu combination.
2. Run/inspect the latest real DigitalOcean lifecycle; stable releases must not proceed without a green E2E.
3. Run locally:

   ```bash
   bundle exec rake ci
   bundle exec rake integration
   ```

4. Move `Unreleased` entries into a dated version section and restore an empty `Unreleased` section.
5. Update `lib/kitsune/kit/version.rb` once. The version must match the intended `vVERSION` tag.
6. Build and inspect:

   ```bash
   bundle exec rake build
   gem specification pkg/kitsune-kit-VERSION.gem
   gem contents --show-install-dir kitsune-kit # after isolated install
   ```

7. Install the artifact in a clean gem directory and run `kit version`, `kit help`, and a temporary `kit init`.
8. Commit the version/changelog, obtain review, merge and create a signed or protected `vVERSION` tag.
9. Push only the tag. Approve the protected `release` environment after rechecking the commit/tag/version.
10. Confirm RubyGems version/checksum, generated GitHub Release and installation from RubyGems.

## Recovery

Do not overwrite/reuse a published version. If publishing succeeds but GitHub Release creation fails, create the release for the same immutable tag/artifact. If a package is defective, publish a new patch version and document the problem. Follow RubyGems owner/yank guidance only for a genuine security or legal incident.
