#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
user="${2:?user is required}"
backup_dir="/var/lib/kitsune/backups/user-${user}"
sudoers_file="/etc/sudoers.d/${user}"
ssh_dir="/home/${user}/.ssh"
authorized_keys="${ssh_dir}/authorized_keys"

validate_user() {
  [[ "${user}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
    echo "invalid user name" >&2
    exit 2
  }
}

snapshot_existing_user() {
  touch "${backup_dir}/existed-before"
  id -nG "${user}" | tr ' ' '\n' | grep -Fxq sudo && touch "${backup_dir}/sudo-before"
  if [[ -f "${sudoers_file}" ]]; then
    cp --preserve=mode,ownership "${sudoers_file}" "${backup_dir}/sudoers.before"
  else
    touch "${backup_dir}/sudoers-absent"
  fi
  if [[ -d "${ssh_dir}" ]]; then
    touch "${backup_dir}/ssh-dir-before"
    stat -c '%a' "${ssh_dir}" > "${backup_dir}/ssh-dir-mode"
  fi
  if [[ -f "${authorized_keys}" ]]; then
    cp --preserve=mode,ownership "${authorized_keys}" "${backup_dir}/authorized_keys.before"
  else
    touch "${backup_dir}/authorized-keys-absent"
  fi
}

apply() {
  validate_user
  if [[ ! -s /root/.ssh/authorized_keys ]]; then
    echo "root authorized_keys is missing or empty" >&2
    exit 1
  fi
  install -d -m 0700 "${backup_dir}"
  if [[ ! -f "${backup_dir}/snapshot-complete" ]]; then
    if id "${user}" >/dev/null 2>&1; then
      snapshot_existing_user
    else
      useradd --create-home --shell /bin/bash "${user}"
      touch "${backup_dir}/created"
    fi
    touch "${backup_dir}/snapshot-complete"
  fi

  usermod -aG sudo "${user}"
  temporary="$(mktemp)"
  trap 'rm -f "${temporary}"' EXIT
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${user}" > "${temporary}"
  chmod 0440 "${temporary}"
  visudo -cf "${temporary}" >/dev/null
  install -o root -g root -m 0440 "${temporary}" "${sudoers_file}"
  rm -f "${temporary}"
  trap - EXIT

  install -d -o "${user}" -g "${user}" -m 0700 "${ssh_dir}"
  install -o "${user}" -g "${user}" -m 0600 /root/.ssh/authorized_keys "${authorized_keys}"
}

verify() {
  validate_user
  id "${user}" >/dev/null
  test -s "${authorized_keys}"
  test "$(stat -c '%a' "${ssh_dir}")" = "700"
  test "$(stat -c '%a' "${authorized_keys}")" = "600"
  visudo -cf "${sudoers_file}" >/dev/null
}

restore_existing_user() {
  if [[ ! -f "${backup_dir}/sudo-before" ]]; then
    gpasswd -d "${user}" sudo || true
  fi
  if [[ -f "${backup_dir}/sudoers.before" ]]; then
    cp --preserve=mode,ownership "${backup_dir}/sudoers.before" "${sudoers_file}"
  elif [[ -f "${backup_dir}/sudoers-absent" ]]; then
    rm -f "${sudoers_file}"
  fi
  if [[ -f "${backup_dir}/authorized_keys.before" ]]; then
    cp --preserve=mode,ownership "${backup_dir}/authorized_keys.before" "${authorized_keys}"
  elif [[ -f "${backup_dir}/authorized-keys-absent" ]]; then
    rm -f "${authorized_keys}"
  fi
  if [[ -f "${backup_dir}/ssh-dir-before" ]]; then
    chmod "$(< "${backup_dir}/ssh-dir-mode")" "${ssh_dir}"
  else
    rm -rf "${ssh_dir}"
  fi
}

rollback() {
  validate_user
  if [[ -f "${backup_dir}/created" ]]; then
    rm -f "${sudoers_file}"
    userdel --remove "${user}" || true
  elif [[ -f "${backup_dir}/existed-before" ]]; then
    restore_existing_user
  fi
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
