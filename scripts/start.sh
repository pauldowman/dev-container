#!/bin/sh
set -e

mkdir -p ~/.ssh
echo "$SSH_AUTHORIZED_KEYS" > ~/.ssh/authorized_keys
echo "$SSH_AUTHORIZED_KEYS" | head -n1 > ~/.ssh/id_ed25519.pub
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_ed25519.pub

sudo mkdir -p /run/sshd
sudo update-ca-certificates >/dev/null

exec sudo /usr/sbin/sshd -D
