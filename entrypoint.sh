#!/bin/bash
set -e

sudo update-ca-certificates &>/dev/null || true
sudo chmod 777 /run/host-services/ssh-auth.sock 2>/dev/null || true

exec "$@"
