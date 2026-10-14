#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 IMAGE" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="$1"
FIXTURE_ROOT="$(mktemp -d "$ROOT/.codex-smoke.XXXXXX")"
CONTAINER_NAME="codex-smoke-$$-$RANDOM"
container_id=""

cleanup() {
  if [[ -n "$container_id" ]]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

docker run --rm --entrypoint /bin/bash "$IMAGE" -ceu '
  curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh
  PATH="$HOME/.local/bin:$PATH" CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DIR="$HOME/.local/bin" sh /tmp/install-codex.sh
  test "$(zsh -c "command -v codex")" = "$HOME/.local/bin/codex"
'

ssh-keygen -q -t ed25519 -N '' -f "$FIXTURE_ROOT/login-key"
mkdir -p "$FIXTURE_ROOT/repo/data/home"
printf 'listed\n' > "$FIXTURE_ROOT/repo/data/home/.persist-smoke"
printf '.persist-smoke\n' > "$FIXTURE_ROOT/repo/data/persist"
mkdir -p "$FIXTURE_ROOT/repo/data/certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=dev-container smoke test" \
  -keyout "$FIXTURE_ROOT/smoke.key" -out "$FIXTURE_ROOT/repo/data/certs/smoke-test.crt" 2>/dev/null
username="$(docker run --rm --entrypoint id "$IMAGE" -un)"

container_id="$(docker run -d \
  --name "$CONTAINER_NAME" \
  --env CODE_DIR="$FIXTURE_ROOT" \
  --env SSH_AUTHORIZED_KEYS="$(cat "$FIXTURE_ROOT/login-key.pub")" \
  --volume "$FIXTURE_ROOT:$FIXTURE_ROOT" \
  --volume "$FIXTURE_ROOT/repo/data:/var/lib/dev-container/data" \
  "$IMAGE")"

literal_dollar='$'
remote_check="test \"${literal_dollar}(command -v codex)\" = \"${literal_dollar}HOME/.local/bin/codex\" && zsh -ic 'test \"${literal_dollar}(command -v codex)\" = \"${literal_dollar}HOME/.local/bin/codex\"' && codex --version >/dev/null && test -L \"${literal_dollar}HOME/.persist-smoke\" && test -e /etc/ssl/certs/smoke-test.pem"

ssh_ready=false
for _ in {1..60}; do
  # Connect from inside the container so the test does not depend on the runner's network namespace.
  if docker exec --user "$username" "$container_id" ssh -i "$FIXTURE_ROOT/login-key" \
    -o BatchMode=yes \
    -o ConnectTimeout=1 \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$username@localhost" "$remote_check"; then
    ssh_ready=true
    break
  fi
  sleep 0.5
done

if [[ "$ssh_ready" != "true" ]]; then
  echo "Timed out waiting for an SSH login to resolve standalone Codex" >&2
  docker inspect "$container_id" --format 'status={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' >&2 || true
  docker logs "$container_id" >&2 || true
  exit 1
fi
