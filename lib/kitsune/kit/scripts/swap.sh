#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
size_gb="${2:?size is required}"
swappiness="${3:?swappiness is required}"
swap_file="/swapfile"
sysctl_file="/etc/sysctl.d/90-kitsune-swap.conf"
backup_dir="/var/lib/kitsune/backups/swap"
sysctl_backup="${backup_dir}/90-kitsune-swap.conf.before"

validate() {
  [[ "${size_gb}" =~ ^[0-9]+$ ]] && (( size_gb >= 0 && size_gb <= 64 ))
  [[ "${swappiness}" =~ ^[0-9]+$ ]] && (( swappiness >= 0 && swappiness <= 100 ))
}

apply() {
  validate
  install -d -m 0700 "${backup_dir}"
  if [[ ! -f "${backup_dir}/sysctl-snapshot" ]]; then
    if [[ -f "${sysctl_file}" ]]; then
      cp --preserve=mode,ownership "${sysctl_file}" "${sysctl_backup}"
    else
      touch "${backup_dir}/sysctl-absent"
    fi
    touch "${backup_dir}/sysctl-snapshot"
  fi
  active=false
  swapon --show=NAME --noheadings | grep -Fxq "${swap_file}" && active=true
  if (( size_gb == 0 )) && [[ -f "${backup_dir}/swap-created" ]]; then
    [[ "${active}" == true ]] && swapoff "${swap_file}"
    rm -f "${swap_file}"
    sed -i '\|/swapfile none swap sw 0 0|d' /etc/fstab
    rm -f "${backup_dir}/current-size"
  elif [[ "${active}" == true ]] && [[ ! -f "${backup_dir}/swap-created" ]]; then
    touch "${backup_dir}/swap-existed"
  elif (( size_gb > 0 )) && [[ -e "${swap_file}" && ! -f "${backup_dir}/swap-created" ]]; then
    echo "refusing to overwrite unmanaged ${swap_file}" >&2
    exit 3
  elif (( size_gb > 0 )) && { [[ "${active}" == false ]] || \
       [[ "$(cat "${backup_dir}/current-size" 2>/dev/null || true)" != "${size_gb}" ]]; }; then
    [[ "${active}" == true ]] && swapoff "${swap_file}"
    fallocate -l "${size_gb}G" "${swap_file}"
    touch "${backup_dir}/swap-created"
    chmod 0600 "${swap_file}"
    mkswap "${swap_file}"
    swapon "${swap_file}"
    grep -Fq "${swap_file} none swap sw 0 0" /etc/fstab || printf '%s none swap sw 0 0\n' "${swap_file}" >> /etc/fstab
    printf '%s\n' "${size_gb}" > "${backup_dir}/current-size"
  fi
  printf 'vm.swappiness=%s\n' "${swappiness}" > "${sysctl_file}"
  sysctl --load "${sysctl_file}"
}

verify() {
  validate
  if (( size_gb > 0 )); then
    swapon --show=NAME --noheadings | grep -Fxq "${swap_file}"
    if [[ -f "${backup_dir}/swap-created" ]]; then
      test "$(stat -c '%s' "${swap_file}")" -ge "$((size_gb * 1024 * 1024 * 1024))"
    fi
  fi
  test "$(sysctl -n vm.swappiness)" = "${swappiness}"
}

rollback() {
  if [[ -f "${backup_dir}/swap-created" ]]; then
    swapoff "${swap_file}" || true
    rm -f "${swap_file}"
    sed -i '\|/swapfile none swap sw 0 0|d' /etc/fstab
  fi
  if [[ -f "${sysctl_backup}" ]]; then
    cp --preserve=mode,ownership "${sysctl_backup}" "${sysctl_file}"
  elif [[ -f "${backup_dir}/sysctl-absent" ]]; then
    rm -f "${sysctl_file}"
  fi
  sysctl --system >/dev/null
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
