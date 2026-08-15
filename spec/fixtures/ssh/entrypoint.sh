#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${AUTHORIZED_KEY:-}" ]]; then
  echo "AUTHORIZED_KEY is required" >&2
  exit 64
fi

install -d -m 0700 /root/.ssh
printf '%s\n' "$AUTHORIZED_KEY" > /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
ssh-keygen -A

exec /usr/sbin/sshd -D -e \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o PermitRootLogin=prohibit-password
