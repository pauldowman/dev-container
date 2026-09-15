#!/bin/sh
set -e

if [ -z "${DEV_CONTAINER_REPO_DIR:-}" ]; then
  echo "Error: DEV_CONTAINER_REPO_DIR must be set by the host launcher" >&2
  exit 1
fi

persistent_home="$DEV_CONTAINER_REPO_DIR/data/home"
sudo mkdir -p "$persistent_home"
sudo chown "$(id -u):$(id -g)" "$persistent_home"
/usr/local/bin/link-home "$persistent_home" "$HOME"

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

# Keep ~/.ssh/agent.sock pointing at a live forwarded agent socket even when
# no shell or connection triggers a repair (see scripts/ssh-agent-relink)
while :; do /usr/local/bin/ssh-agent-relink || true; sleep 60; done &

exec sudo /usr/sbin/sshd -D
