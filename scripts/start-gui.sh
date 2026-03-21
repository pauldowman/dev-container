#!/bin/sh
set -e

mkdir -p ~/.ssh
echo "$SSH_AUTHORIZED_KEYS" > ~/.ssh/authorized_keys
echo "$SSH_AUTHORIZED_KEYS" | head -n1 > ~/.ssh/id_ed25519.pub
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519.pub

sudo mkdir -p /run/sshd
sudo update-ca-certificates >/dev/null

echo "DISPLAY=:10" | sudo tee -a /etc/environment >/dev/null

echo "Starting xrdp-sesman..."
sudo xrdp-sesman
until [ -f /var/run/xrdp/xrdp-sesman.pid ]; do
    echo "Waiting for xrdp-sesman..."
    sleep 0.2
done
echo "xrdp-sesman ready"

echo "Starting xrdp..."
sudo xrdp
until [ -f /var/run/xrdp/xrdp.pid ]; do
    echo "Waiting for xrdp..."
    sleep 0.2
done
echo "xrdp ready"

exec sudo /usr/sbin/sshd -D
