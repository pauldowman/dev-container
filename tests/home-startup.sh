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
grep -Fq "persistent_home=\"${literal_dollar}DEV_CONTAINER_REPO_DIR/data/home\"" "$ROOT/scripts/start.sh" || fail "Startup must use the repository data/home source"
grep -Fq "sudo mkdir -p \"${literal_dollar}persistent_home\"" "$ROOT/scripts/start.sh" || fail "Startup must create data/home with elevated access"
grep -Fq "sudo chown \"${literal_dollar}(id -u):${literal_dollar}(id -g)\" \"${literal_dollar}persistent_home\"" "$ROOT/scripts/start.sh" || fail "Startup must assign data/home to the runtime user"

link_line="$(grep -nF "/usr/local/bin/link-home \"${literal_dollar}persistent_home\" \"${literal_dollar}HOME\"" "$ROOT/scripts/start.sh" | cut -d: -f1)"
authorized_keys_line="$(grep -nF "echo \"${literal_dollar}SSH_AUTHORIZED_KEYS\" >~/.ssh/authorized_keys" "$ROOT/scripts/start.sh" | cut -d: -f1)"
[[ -n "$link_line" && -n "$authorized_keys_line" && "$link_line" -lt "$authorized_keys_line" ]] || fail "Home links must be installed before runtime SSH files are written"
