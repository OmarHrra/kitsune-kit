#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: script/smoke-gem-artifact.sh PATH_TO_GEM" >&2
  exit 64
fi

artifact="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
if [[ ! -f "${artifact}" ]]; then
  echo "Gem artifact not found: ${artifact}" >&2
  exit 66
fi

install_root="$(mktemp -d "${TMPDIR:-/tmp}/kitsune-kit-artifact.XXXXXX")"
trap 'rm -rf -- "${install_root}"' EXIT

env -u BUNDLE_GEMFILE gem install --no-document --install-dir "${install_root}" "${artifact}"

kit="${install_root}/bin/kit"
runtime=(env -u BUNDLE_GEMFILE "GEM_HOME=${install_root}" "GEM_PATH=${install_root}")
expected_version="$(ruby -rrubygems/package -e 'puts Gem::Package.new(ARGV.fetch(0)).spec.version' "${artifact}")"

version_output="$(cd "${install_root}" && "${runtime[@]}" "${kit}" version)"
if [[ "${version_output}" != "Kitsune Kit ${expected_version}" ]]; then
  echo "Unexpected version output: ${version_output}" >&2
  exit 1
fi

help_output="$(cd "${install_root}" && "${runtime[@]}" "${kit}" help)"
actual_commands="$(printf '%s\n' "${help_output}" | sed -n 's/^  kit \([^ ]*\).*/\1/p' | LC_ALL=C sort)"
expected_commands="$(printf '%s\n' \
  apply dns docker doctor env help init plan resume rollback server service status support ui version | LC_ALL=C sort)"

if [[ "${actual_commands}" != "${expected_commands}" ]]; then
  echo "Installed artifact exposed an unexpected public command set." >&2
  echo "Expected:" >&2
  printf '%s\n' "${expected_commands}" >&2
  echo "Actual:" >&2
  printf '%s\n' "${actual_commands}" >&2
  exit 1
fi

project_root="${install_root}/smoke-project"
init_output="$(cd "${install_root}" && "${runtime[@]}" "${kit}" init --root "${project_root}")"
if [[ ! -f "${project_root}/.kitsune/config.yml" || ! -f "${project_root}/.gitignore" ]]; then
  echo "Installed artifact did not initialize the expected project files." >&2
  printf '%s\n' "${init_output}" >&2
  exit 1
fi

printf '%s\n' "${version_output}"
printf '%s\n' "Artifact CLI commands: ${actual_commands//$'\n'/, }"
printf '%s\n' "Artifact project initialization: ok"
