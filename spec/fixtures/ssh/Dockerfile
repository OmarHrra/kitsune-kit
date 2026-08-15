ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --yes --no-install-recommends openssh-server ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /root/.ssh \
    && chmod 0700 /root/.ssh

COPY entrypoint.sh /usr/local/bin/kitsune-sshd-entrypoint
RUN chmod 0755 /usr/local/bin/kitsune-sshd-entrypoint

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/kitsune-sshd-entrypoint"]
