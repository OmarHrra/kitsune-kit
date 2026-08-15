#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
expected_sha256="${2:?installer SHA-256 is required}"
backup_dir="/var/lib/kitsune/backups/metrics"
apt_options=(-o DPkg::Lock::Timeout=120 -o Acquire::Retries=3)

apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" "$@"
}

validate() {
  [[ "${expected_sha256}" =~ ^[a-f0-9]{64}$ ]] || {
    echo "invalid installer SHA-256" >&2
    exit 2
  }
}

apply() {
  validate
  install -d -m 0700 "${backup_dir}"
  if dpkg-query -W -f='${Status}' do-agent 2>/dev/null | grep -q "ok installed"; then
    touch "${backup_dir}/package-existed"
    return
  fi
  installer="$(mktemp)"
  trap 'rm -f "${installer}"' EXIT
  curl --fail --silent --show-error --location \
    https://repos.insights.digitalocean.com/install.sh --output "${installer}"
  test -s "${installer}"
  printf '%s  %s\n' "${expected_sha256}" "${installer}" | sha256sum --check --status
  bash -n "${installer}"
  bash "${installer}"
  rm -f "${installer}"
  trap - EXIT
  touch "${backup_dir}/package-created"
}

verify() {
  validate
  dpkg-query -W -f='${Status}' do-agent 2>/dev/null | grep -q "ok installed"
  systemctl is-active --quiet do-agent
}

rollback() {
  if [[ -f "${backup_dir}/package-created" ]]; then
    systemctl disable --now do-agent || true
    apt_get remove --purge --yes do-agent || true
  fi
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
