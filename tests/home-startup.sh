#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "$*" >&2
  exit 1
}

grep -Fxq 'data/' "$ROOT/.dockerignore" || fail "data/ must be excluded from the Docker build context"
grep -Fq 'COPY scripts/link-home /usr/local/bin/link-home' "$ROOT/Dockerfile" || fail "Dockerfile must install link-home"
literal_dollar='$'
grep -Fxq "data_dir=/var/lib/dev-container/data" "$ROOT/scripts/start.sh" || fail "Startup must use the fixed data mount"
grep -Fq "persistent_home=\"${literal_dollar}data_dir/home\"" "$ROOT/scripts/start.sh" || fail "Startup must use the mounted data/home source"
grep -Fq "sudo mkdir -p \"${literal_dollar}persistent_home\"" "$ROOT/scripts/start.sh" || fail "Startup must create data/home with elevated access"
grep -Fq "sudo chown \"${literal_dollar}(id -u):${literal_dollar}(id -g)\" \"${literal_dollar}persistent_home\"" "$ROOT/scripts/start.sh" || fail "Startup must assign data/home to the runtime user"

link_line="$(grep -nF "/usr/local/bin/link-home \"${literal_dollar}persistent_home\" \"${literal_dollar}data_dir/persist\" \"${literal_dollar}HOME\"" "$ROOT/scripts/start.sh" | cut -d: -f1)"
authorized_keys_line="$(grep -nF "echo \"${literal_dollar}SSH_AUTHORIZED_KEYS\" >~/.ssh/authorized_keys" "$ROOT/scripts/start.sh" | cut -d: -f1)"
[[ -n "$link_line" && -n "$authorized_keys_line" && "$link_line" -lt "$authorized_keys_line" ]] || fail "Home links must be installed before runtime SSH files are written"

copy_line="$(grep -nF "sudo find \"${literal_dollar}data_dir/certs\" -maxdepth 1 -type f -name '*.crt' -exec cp -- {} \"${literal_dollar}cert_dir/\" \\;" "$ROOT/scripts/start.sh" | cut -d: -f1)"
update_line="$(grep -nF "sudo update-ca-certificates --fresh" "$ROOT/scripts/start.sh" | cut -d: -f1)"
clear_line="$(grep -nF "sudo rm -rf \"${literal_dollar}cert_dir\"" "$ROOT/scripts/start.sh" | cut -d: -f1)"
[[ -n "$clear_line" && -n "$copy_line" && -n "$update_line" && "$clear_line" -lt "$copy_line" && "$copy_line" -lt "$update_line" ]] || fail "Certificates must be cleared, then copied from data/certs, before update-ca-certificates"
