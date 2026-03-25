#!/bin/sh
set -e

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

exec "$(dirname "$0")/start.sh"
