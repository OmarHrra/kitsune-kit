#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
user="${2:?user is required}"
config_file="/etc/ssh/sshd_config.d/90-kitsune.conf"
backup_dir="/var/lib/kitsune/backups/ssh"
backup_file="${backup_dir}/90-kitsune.conf.before"

validate_user() {
  [[ "${user}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
    echo "invalid user name" >&2
    exit 2
  }
}

reload_ssh() {
  sshd -t
  systemctl reload ssh 2>/dev/null || systemctl reload sshd
}

write_policy() {
  local root_policy="$1"
  local temporary
  temporary="$(mktemp)"
  trap 'rm -f "${temporary}"' EXIT
  cat > "${temporary}" <<EOF
# Managed by Kitsune Kit. Local changes will be replaced.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin ${root_policy}
AllowUsers ${user}
EOF
  install -o root -g root -m 0644 "${temporary}" "${config_file}"
  rm -f "${temporary}"
  trap - EXIT
  reload_ssh
}

apply() {
  validate_user
  install -d -m 0700 "${backup_dir}"
  if [[ ! -f "${backup_dir}/snapshot-complete" ]]; then
    if [[ -f "${config_file}" ]]; then
      cp --preserve=mode,ownership "${config_file}" "${backup_file}"
    else
      touch "${backup_dir}/absent-before"
    fi
    touch "${backup_dir}/snapshot-complete"
  fi

  # Keep key-based root recovery until Kitsune Kit verifies a fresh deploy login.
  write_policy "prohibit-password"
}

verify() {
  validate_user
  sshd -t
  grep -Fxq "PasswordAuthentication no" "${config_file}"
  grep -Fxq "PermitRootLogin prohibit-password" "${config_file}"
  grep -Fxq "AllowUsers ${user}" "${config_file}"
}

finalize() {
  validate_user
  write_policy "no"
}

verify_final() {
  validate_user
  sshd -t
  grep -Fxq "PasswordAuthentication no" "${config_file}"
  grep -Fxq "PermitRootLogin no" "${config_file}"
  grep -Fxq "AllowUsers ${user}" "${config_file}"
}

rollback() {
  if [[ -f "${backup_file}" ]]; then
    cp --preserve=mode,ownership "${backup_file}" "${config_file}"
  elif [[ -f "${backup_dir}/absent-before" ]]; then
    rm -f "${config_file}"
  fi
  reload_ssh
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  finalize) finalize ;;
  verify_final) verify_final ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
