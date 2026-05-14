#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

copy_runtime() {
  mkdir -p "$TMP_DIR/scripts" "$TMP_DIR/bin"
  cp "$ROOT/build" "$ROOT/start" "$ROOT/dev" "$TMP_DIR/"
  cp "$ROOT/scripts/env.sh" "$TMP_DIR/scripts/"
}

write_stubs() {
  cat > "$TMP_DIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *" port dev-container 22"* ]]; then
  echo "0.0.0.0:${SSH_PORT:-2222}"
  exit 0
fi
if [[ "$*" == *" ps -q dev-container"* ]]; then
  exit 0
fi
if [[ "${1:-}" == "inspect" ]]; then
  echo "false"
  exit 0
fi
echo "docker INSTANCE=${INSTANCE:-} SSH_PORT=${SSH_PORT:-} CODE_DIR=${CODE_DIR:-} DOCKERFILE=${DOCKERFILE:-} args=$*"
STUB

  cat > "$TMP_DIR/bin/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh GH_TOKEN=${GH_TOKEN:-} args=$*"
STUB

  chmod +x "$TMP_DIR/bin/docker" "$TMP_DIR/bin/ssh"
}

assert_contains() {
  local output="$1"
  local expected="$2"

  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

copy_runtime
write_stubs

cat > "$TMP_DIR/.env" <<'ENV'
CODE_DIR=/shared/code
DOCKERFILE=Dockerfile
GH_TOKEN=shared-token
SSH_PORT=2222
USERNAME=tester
ENV

cat > "$TMP_DIR/.env.work" <<'ENV'
CODE_DIR=/work/code
DOCKERFILE=Dockerfile.gui
GH_TOKEN=work-token
SSH_PORT=2223
ENV

export PATH="$TMP_DIR/bin:$PATH"
export SSH_AUTH_SOCK=/tmp/fake-ssh-agent.sock

start_output="$("$TMP_DIR/start" --instance work)"
assert_contains "$start_output" "INSTANCE=work"
assert_contains "$start_output" "SSH_PORT=2223"
assert_contains "$start_output" "CODE_DIR=/work/code"

fallback_output="$("$TMP_DIR/start" --instance scratch)"
assert_contains "$fallback_output" "INSTANCE=scratch"
assert_contains "$fallback_output" "SSH_PORT=2222"
assert_contains "$fallback_output" "CODE_DIR=/shared/code"

start_override_output="$("$TMP_DIR/start" --instance work --ssh-port 3333)"
assert_contains "$start_override_output" "INSTANCE=work"
assert_contains "$start_override_output" "SSH_PORT=3333"

build_output="$("$TMP_DIR/build" --instance work --progress plain)"
assert_contains "$build_output" "INSTANCE=work"
assert_contains "$build_output" "DOCKERFILE=Dockerfile.gui"
assert_contains "$build_output" "args=compose -p work build --progress plain"

dev_output="$("$TMP_DIR/dev" --instance work project)"
assert_contains "$dev_output" "Connecting to tester@localhost:2223 (work)..."
assert_contains "$dev_output" "GH_TOKEN=work-token"
assert_contains "$dev_output" "-c /work/code/project"
