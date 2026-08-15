#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
config_file="/etc/apt/apt.conf.d/20auto-upgrades"
backup_dir="/var/lib/kitsune/backups/unattended"
backup_file="${backup_dir}/20auto-upgrades.before"
packages=(unattended-upgrades apt-listchanges)
apt_options=(-o DPkg::Lock::Timeout=120 -o Acquire::Retries=3)

apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" "$@"
}

snapshot() {
  [[ -f "${backup_dir}/snapshot-complete" ]] && return
  : > "${backup_dir}/packages-before"
  for package in "${packages[@]}"; do
    if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "ok installed"; then
      printf '%s\n' "${package}" >> "${backup_dir}/packages-before"
    fi
  done
  systemctl is-enabled --quiet unattended-upgrades.service && touch "${backup_dir}/enabled-before"
  systemctl is-active --quiet unattended-upgrades.service && touch "${backup_dir}/active-before"
  if [[ -f "${config_file}" ]]; then
    cp --preserve=mode,ownership "${config_file}" "${backup_file}"
  else
    touch "${backup_dir}/config-absent"
  fi
  touch "${backup_dir}/snapshot-complete"
}

apply() {
  install -d -m 0700 "${backup_dir}"
  snapshot
  apt_get update
  apt_get install --yes "${packages[@]}"
  cat > "${config_file}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now unattended-upgrades.service
}

verify() {
  test -f "${config_file}"
  systemctl is-enabled --quiet unattended-upgrades.service
  systemctl is-active --quiet unattended-upgrades.service
}

restore_service_state() {
  if [[ -f "${backup_dir}/enabled-before" ]]; then
    systemctl enable unattended-upgrades.service || true
  else
    systemctl disable unattended-upgrades.service || true
  fi
  if [[ -f "${backup_dir}/active-before" ]]; then
    systemctl start unattended-upgrades.service || true
  else
    systemctl stop unattended-upgrades.service || true
  fi
}

rollback() {
  if [[ -f "${backup_file}" ]]; then
    cp --preserve=mode,ownership "${backup_file}" "${config_file}"
  elif [[ -f "${backup_dir}/config-absent" ]]; then
    rm -f "${config_file}"
  fi
  restore_service_state
  for package in "${packages[@]}"; do
    if ! grep -Fxq "${package}" "${backup_dir}/packages-before" 2>/dev/null; then
      apt_get remove --yes "${package}" || true
    fi
  done
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
