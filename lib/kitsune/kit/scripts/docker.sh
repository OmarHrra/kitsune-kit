#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?action is required}"
user="${2:?user is required}"
backup_dir="/var/lib/kitsune/backups/docker"
keyring="/etc/apt/keyrings/docker.asc"
repository="/etc/apt/sources.list.d/docker.sources"
packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
prerequisites=(ca-certificates curl)
conflicting_packages=(docker.io docker-compose docker-compose-v2 podman-docker containerd runc)

refuse_conflicting_packages() {
  local installed=()
  local package
  for package in "${conflicting_packages[@]}"; do
    if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "ok installed"; then
      installed+=("${package}")
    fi
  done
  if (( ${#installed[@]} > 0 )); then
    printf 'conflicting Docker packages are installed: %s\n' "${installed[*]}" >&2
    echo "Remove or migrate them explicitly before Kitsune Kit installs Docker CE." >&2
    exit 3
  fi
}

snapshot() {
  [[ -f "${backup_dir}/snapshot-complete" ]] && return
  : > "${backup_dir}/packages-before"
  for package in "${prerequisites[@]}" "${packages[@]}"; do
    if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "ok installed"; then
      printf '%s\n' "${package}" >> "${backup_dir}/packages-before"
    fi
  done
  systemctl is-enabled --quiet docker && touch "${backup_dir}/enabled-before"
  systemctl is-active --quiet docker && touch "${backup_dir}/active-before"
  touch "${backup_dir}/snapshot-complete"
}

apply() {
  refuse_conflicting_packages
  install -d -m 0700 "${backup_dir}"
  snapshot
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --yes "${prerequisites[@]}"
  install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f "${keyring}" ]]; then
    temporary_key="$(mktemp)"
    trap 'rm -f "${temporary_key}"' EXIT
    curl --fail --silent --show-error --location \
      https://download.docker.com/linux/ubuntu/gpg --output "${temporary_key}"
    test -s "${temporary_key}"
    install -o root -g root -m 0644 "${temporary_key}" "${keyring}"
    rm -f "${temporary_key}"
    trap - EXIT
    touch "${backup_dir}/key-created"
  fi
  if [[ ! -f "${repository}" ]]; then
    codename="$(sed -n 's/^UBUNTU_CODENAME=//p' /etc/os-release | tr -d '\"')"
    if [[ -z "${codename}" ]]; then
      codename="$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | tr -d '\"')"
    fi
    [[ -n "${codename}" ]] || { echo "cannot determine Ubuntu codename" >&2; exit 1; }
    temporary_repository="$(mktemp)"
    trap 'rm -f "${temporary_repository}"' EXIT
    cat > "${temporary_repository}" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: ${keyring}
EOF
    install -o root -g root -m 0644 "${temporary_repository}" "${repository}"
    rm -f "${temporary_repository}"
    trap - EXIT
    touch "${backup_dir}/repository-created"
  fi
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install --yes "${packages[@]}"
  systemctl enable --now docker
  if ! id -nG "${user}" | tr ' ' '\n' | grep -Fxq docker; then
    usermod -aG docker "${user}"
    touch "${backup_dir}/group-added"
  fi
  if ! docker network inspect kitsune-private >/dev/null 2>&1; then
    docker network create --driver bridge kitsune-private >/dev/null
    touch "${backup_dir}/network-created"
  fi
}

verify() {
  systemctl is-active --quiet docker
  docker version >/dev/null
  docker compose version >/dev/null
  id -nG "${user}" | tr ' ' '\n' | grep -Fxq docker
  docker network inspect kitsune-private >/dev/null
}

rollback() {
  if [[ -f "${backup_dir}/group-added" ]]; then
    gpasswd -d "${user}" docker || true
  fi
  if [[ -f "${backup_dir}/network-created" ]]; then
    docker network rm kitsune-private || true
  fi
  for package in "${packages[@]}"; do
    if ! grep -Fxq "${package}" "${backup_dir}/packages-before" 2>/dev/null; then
      apt-get remove --yes "${package}" || true
    fi
  done
  for package in "${prerequisites[@]}"; do
    if ! grep -Fxq "${package}" "${backup_dir}/packages-before" 2>/dev/null; then
      apt-get remove --yes "${package}" || true
    fi
  done
  if [[ -f "${backup_dir}/enabled-before" ]]; then
    systemctl enable docker || true
  else
    systemctl disable docker || true
  fi
  if [[ -f "${backup_dir}/active-before" ]]; then
    systemctl start docker || true
  else
    systemctl stop docker || true
  fi
  [[ -f "${backup_dir}/repository-created" ]] && rm -f "${repository}"
  [[ -f "${backup_dir}/key-created" ]] && rm -f "${keyring}"
  rm -rf "${backup_dir}"
}

case "${action}" in
  apply) apply ;;
  verify) verify ;;
  rollback) rollback ;;
  *) echo "unknown action: ${action}" >&2; exit 2 ;;
esac
