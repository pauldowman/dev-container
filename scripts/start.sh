#!/bin/sh
set -e

data_dir=/var/lib/dev-container/data
persistent_home="$data_dir/home"
sudo mkdir -p "$persistent_home"
sudo chown "$(id -u):$(id -g)" "$persistent_home"
/usr/local/bin/link-home "$persistent_home" "$data_dir/persist" "$HOME"

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

# Copied rather than bind-mounted: the container can replace data/certs with a
# symlink, which Docker would resolve on the host when recreating a nested mount.
cert_dir=/usr/local/share/ca-certificates/dev-container
sudo rm -rf "$cert_dir"
sudo mkdir -p "$cert_dir"
if [ -d "$data_dir/certs" ]; then
  sudo find "$data_dir/certs" -maxdepth 1 -type f -name '*.crt' -exec cp -- {} "$cert_dir/" \;
fi
sudo update-ca-certificates --fresh >/dev/null

# Keep ~/.ssh/agent.sock pointing at an agent with the signing key even when
# no shell or connection triggers a repair (see scripts/ssh-agent-relink)
while :; do
  /usr/local/bin/ssh-agent-relink || true
  sleep 60
done &

exec sudo /usr/sbin/sshd -D
