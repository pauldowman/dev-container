#!/bin/sh
set -e

mkdir -p ~/.ssh
echo "$SSH_AUTHORIZED_KEYS" >~/.ssh/authorized_keys
echo "$SSH_AUTHORIZED_KEYS" | head -n1 >~/.ssh/id_ed25519.pub
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519.pub

# Grant the user access to the Docker socket if mounted
if [ -S /var/run/docker.sock ]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  sudo groupadd -g "$DOCKER_GID" docker 2>/dev/null || true
  DOCKER_GROUP=$(getent group "$DOCKER_GID" | cut -d: -f1)
  sudo usermod -aG "$DOCKER_GROUP" "$(whoami)"
fi

sudo mkdir -p /run/sshd
sudo update-ca-certificates >/dev/null

exec sudo /usr/sbin/sshd -D
