#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
ssh_port="${2:?SSH port is required}"
shift 2
allowed_cidrs=("$@")
backup_dir="/var/lib/kitsune/backups/firewall"
added_file="${backup_dir}/rules-added"
pending_file="${backup_dir}/rules-pending"

validate() {
  [[ "${ssh_port}" =~ ^[0-9]+$ ]] && (( ssh_port >= 1 && ssh_port <= 65535 ))
  for cidr in "${allowed_cidrs[@]}"; do
    [[ "${cidr}" =~ ^[0-9a-fA-F:.]+/[0-9]{1,3}$ ]] || {
      echo "invalid CIDR: ${cidr}" >&2
      exit 2
    }
  done
}

global_rule_exists() {
  local port="$1"
  ufw status | grep -Eq "^${port}/tcp[[:space:]]+ALLOW"
}

owned_global_rule_exists() {
  local port="$1"
  local comment="$2"
  ufw status | grep -E "^${port}/tcp[[:space:]]+ALLOW" | grep -Fq "# ${comment}"
}

cidr_rule_exists() {
  local port="$1"
  local cidr="$2"
  ufw status | grep -F "${port}/tcp" | grep -Fq "${cidr}"
}

owned_cidr_rule_exists() {
  local port="$1"
  local cidr="$2"
  local comment="$3"
  ufw status | grep -F "${port}/tcp" | grep -F "${cidr}" | grep -Fq "# ${comment}"
}

ensure_global_rule() {
  local port="$1"
  local comment="$2"
  local next_file="$3"
  local ownership="global|${port}"
  if grep -Fxq "${ownership}" "${added_file}"; then
    owned_global_rule_exists "${port}" "${comment}" || ufw allow "${port}/tcp" comment "${comment}"
    printf '%s\n' "${ownership}" >> "${next_file}"
  elif ! global_rule_exists "${port}"; then
    ufw allow "${port}/tcp" comment "${comment}"
    printf '%s\n' "${ownership}" >> "${next_file}"
  fi
}

ensure_cidr_rule() {
  local port="$1"
  local cidr="$2"
  local comment="$3"
  local next_file="$4"
  local ownership="cidr|${port}|${cidr}"
  if grep -Fxq "${ownership}" "${added_file}"; then
    owned_cidr_rule_exists "${port}" "${cidr}" "${comment}" || \
      ufw allow from "${cidr}" to any port "${port}" proto tcp comment "${comment}"
    printf '%s\n' "${ownership}" >> "${next_file}"
  elif ! cidr_rule_exists "${port}" "${cidr}"; then
    ufw allow from "${cidr}" to any port "${port}" proto tcp comment "${comment}"
    printf '%s\n' "${ownership}" >> "${next_file}"
  fi
}

delete_rule() {
  local kind="$1"
  local port="$2"
  local cidr="${3:-}"
  local comment="kitsune:ssh"
  if [[ "${kind}" == "global" ]]; then
    [[ "${port}" == "80" ]] && comment="kitsune:http"
    [[ "${port}" == "443" ]] && comment="kitsune:https"
    ufw --force delete allow "${port}/tcp" comment "${comment}" || true
  else
    ufw --force delete allow from "${cidr}" to any port "${port}" proto tcp comment "${comment}" || true
  fi
}

remove_stale_owned_rules() {
  local next_file="$1"
  local kind port cidr ownership
  while IFS='|' read -r kind port cidr; do
    [[ -z "${kind}" ]] && continue
    ownership="${kind}|${port}"
    [[ -n "${cidr}" ]] && ownership+="|${cidr}"
    grep -Fxq "${ownership}" "${next_file}" || delete_rule "${kind}" "${port}" "${cidr}"
  done < "${added_file}"
}

cleanup_new_rules() {
  [[ -n "${next_file:-}" && -f "${next_file}" ]] || return
  local kind port cidr ownership
  while IFS='|' read -r kind port cidr; do
    [[ -z "${kind}" ]] && continue
    ownership="${kind}|${port}"
    [[ -n "${cidr}" ]] && ownership+="|${cidr}"
    grep -Fxq "${ownership}" "${added_file}" || delete_rule "${kind}" "${port}" "${cidr}"
  done < "${next_file}"
  rm -f "${next_file}"
}

apply() {
  validate
  install -d -m 0700 "${backup_dir}"
  touch "${added_file}"
  if [[ -f "${pending_file}" ]]; then
    merged_file="$(mktemp "${backup_dir}/rules-owned.XXXXXX")"
    sort -u "${added_file}" "${pending_file}" > "${merged_file}"
    mv "${merged_file}" "${added_file}"
    rm -f "${pending_file}"
  fi
  if [[ ! -f "${backup_dir}/snapshot-complete" ]]; then
    if ufw status | grep -Fq "Status: active"; then
      touch "${backup_dir}/active-before"
    fi
    touch "${backup_dir}/snapshot-complete"
  fi
  if ! dpkg-query -W -f='${Status}' ufw 2>/dev/null | grep -q "ok installed"; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install --yes ufw
    touch "${backup_dir}/package-created"
  fi

  next_file="$(mktemp "${backup_dir}/rules-next.XXXXXX")"
  trap cleanup_new_rules ERR INT TERM
  if (( ${#allowed_cidrs[@]} == 0 )); then
    ensure_global_rule "${ssh_port}" "kitsune:ssh" "${next_file}"
  else
    for cidr in "${allowed_cidrs[@]}"; do
      ensure_cidr_rule "${ssh_port}" "${cidr}" "kitsune:ssh" "${next_file}"
    done
  fi
  ensure_global_rule 80 "kitsune:http" "${next_file}"
  ensure_global_rule 443 "kitsune:https" "${next_file}"
  # Keep stale access until Kitsune Kit verifies a fresh SSH connection through
  # the desired rules. The separate finalize action removes it afterward.
  mv "${next_file}" "${pending_file}"
  trap - ERR INT TERM
  ufw --force enable
}

verify() {
  validate
  ufw status | grep -Fq "Status: active"
  ufw status | grep -Eq '^80/tcp[[:space:]]+ALLOW'
  ufw status | grep -Eq '^443/tcp[[:space:]]+ALLOW'
  if (( ${#allowed_cidrs[@]} == 0 )); then
    global_rule_exists "${ssh_port}"
  else
    for cidr in "${allowed_cidrs[@]}"; do
      cidr_rule_exists "${ssh_port}" "${cidr}"
    done
  fi
}

finalize() {
  validate
  [[ -f "${pending_file}" ]] || {
    echo "no pending firewall rule set to finalize" >&2
    exit 4
  }
  remove_stale_owned_rules "${pending_file}"
  mv "${pending_file}" "${added_file}"
}

verify_final() {
  verify
  [[ ! -f "${pending_file}" ]]
}

rollback() {
  if [[ -f "${added_file}" || -f "${pending_file}" ]]; then
    while IFS='|' read -r kind port cidr; do
      [[ -z "${kind}" ]] && continue
      delete_rule "${kind}" "${port}" "${cidr}"
    done < <(cat "${added_file}" "${pending_file}" 2>/dev/null | sort -u)
  fi
  if [[ ! -f "${backup_dir}/active-before" ]]; then
    ufw --force disable || true
  fi
  if [[ -f "${backup_dir}/package-created" ]]; then
    apt-get remove --yes ufw || true
  fi
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
