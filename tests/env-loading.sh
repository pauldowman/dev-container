#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unset BUILD_TARGET DOCKERFILE

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
echo "docker INSTANCE=${INSTANCE:-} SSH_PORT=${SSH_PORT:-} CODE_DIR=${CODE_DIR:-} DEV_CONTAINER_REPO_DIR=${DEV_CONTAINER_REPO_DIR:-} BUILD_TARGET=${BUILD_TARGET:-} args=$*"
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

cat > "$TMP_DIR/.env" <<ENV
CODE_DIR=$TMP_DIR
BUILD_TARGET=base
GH_TOKEN=shared-token
SSH_PORT=2222
USERNAME=tester
ENV

cat > "$TMP_DIR/.env.work" <<ENV
CODE_DIR=$TMP_DIR
BUILD_TARGET=gui
GH_TOKEN=work-token
INSTANCE=bad/name
SSH_PORT=2223
ENV

export PATH="$TMP_DIR/bin:$PATH"
export SSH_AUTH_SOCK=/tmp/fake-ssh-agent.sock

start_output="$("$TMP_DIR/start" --instance work)"
assert_contains "$start_output" "INSTANCE=work"
assert_contains "$start_output" "SSH_PORT=2223"
assert_contains "$start_output" "CODE_DIR=$TMP_DIR"
assert_contains "$start_output" "DEV_CONTAINER_REPO_DIR=$TMP_DIR"
assert_contains "$start_output" "BUILD_TARGET=gui"

fallback_output="$("$TMP_DIR/start" --instance scratch)"
assert_contains "$fallback_output" "INSTANCE=scratch"
assert_contains "$fallback_output" "SSH_PORT=2222"
assert_contains "$fallback_output" "CODE_DIR=$TMP_DIR"
assert_contains "$fallback_output" "DEV_CONTAINER_REPO_DIR=$TMP_DIR"
assert_contains "$fallback_output" "BUILD_TARGET=base"

start_override_output="$("$TMP_DIR/start" --instance work --ssh-port 3333)"
assert_contains "$start_override_output" "INSTANCE=work"
assert_contains "$start_override_output" "SSH_PORT=3333"

build_output="$("$TMP_DIR/build" --instance work --progress plain)"
assert_contains "$build_output" "INSTANCE=work"
assert_contains "$build_output" "DEV_CONTAINER_REPO_DIR=$TMP_DIR"
assert_contains "$build_output" "BUILD_TARGET=gui"
assert_contains "$build_output" "args=compose -p work build --progress plain"

cat > "$TMP_DIR/.env.invalid" <<'ENV'
BUILD_TARGET=desktop
ENV

if invalid_build_output="$("$TMP_DIR/build" --instance invalid 2>&1)"; then
  echo "Expected build to reject an invalid BUILD_TARGET" >&2
  exit 1
fi
assert_contains "$invalid_build_output" "BUILD_TARGET must be base or gui"

if invalid_start_output="$("$TMP_DIR/start" --instance invalid 2>&1)"; then
  echo "Expected start to reject an invalid BUILD_TARGET" >&2
  exit 1
fi
assert_contains "$invalid_start_output" "BUILD_TARGET must be base or gui"

cat > "$TMP_DIR/.env.legacy" <<'ENV'
DOCKERFILE=Dockerfile.gui
ENV

if legacy_build_output="$("$TMP_DIR/build" --instance legacy 2>&1)"; then
  echo "Expected build to reject obsolete DOCKERFILE" >&2
  exit 1
fi
assert_contains "$legacy_build_output" "DOCKERFILE is obsolete"

if legacy_start_output="$("$TMP_DIR/start" --instance legacy 2>&1)"; then
  echo "Expected start to reject obsolete DOCKERFILE" >&2
  exit 1
fi
assert_contains "$legacy_start_output" "DOCKERFILE is obsolete"

mkdir "$TMP_DIR/not-repo-parent"
cat > "$TMP_DIR/.env.outside" <<ENV
CODE_DIR=$TMP_DIR/not-repo-parent
ENV

if outside_build_output="$("$TMP_DIR/build" --instance outside 2>&1)"; then
  echo "Expected build to reject a repository outside CODE_DIR" >&2
  exit 1
fi
assert_contains "$outside_build_output" "repository path must be inside CODE_DIR"

if outside_start_output="$("$TMP_DIR/start" --instance outside 2>&1)"; then
  echo "Expected start to reject a repository outside CODE_DIR" >&2
  exit 1
fi
assert_contains "$outside_start_output" "repository path must be inside CODE_DIR"

cat > "$TMP_DIR/.env.relative" <<'ENV'
CODE_DIR=.
ENV

if relative_build_output="$("$TMP_DIR/build" --instance relative 2>&1)"; then
  echo "Expected build to reject a relative CODE_DIR" >&2
  exit 1
fi
assert_contains "$relative_build_output" "CODE_DIR must be an absolute path"

if relative_start_output="$("$TMP_DIR/start" --instance relative 2>&1)"; then
  echo "Expected start to reject a relative CODE_DIR" >&2
  exit 1
fi
assert_contains "$relative_start_output" "CODE_DIR must be an absolute path"

ln -s "$TMP_DIR" "$TMP_DIR/code-dir-alias"
cat > "$TMP_DIR/.env.symlink" <<ENV
CODE_DIR=$TMP_DIR/code-dir-alias
ENV

if symlink_build_output="$("$TMP_DIR/build" --instance symlink 2>&1)"; then
  echo "Expected build to reject a symlinked CODE_DIR" >&2
  exit 1
fi
assert_contains "$symlink_build_output" "CODE_DIR must be a canonical path"

if symlink_start_output="$("$TMP_DIR/start" --instance symlink 2>&1)"; then
  echo "Expected start to reject a symlinked CODE_DIR" >&2
  exit 1
fi
assert_contains "$symlink_start_output" "CODE_DIR must be a canonical path"

valid_long_instance="$(printf 'a%.0s' {1..123})"
invalid_long_instance="${valid_long_instance}a"
"$TMP_DIR/build" --instance "$valid_long_instance" >/dev/null
"$TMP_DIR/start" --instance "$valid_long_instance" >/dev/null

if long_build_output="$("$TMP_DIR/build" --instance "$invalid_long_instance" 2>&1)"; then
  echo "Expected build to reject an instance longer than 123 characters" >&2
  exit 1
fi
assert_contains "$long_build_output" "instance must be at most 123 characters"

if long_start_output="$("$TMP_DIR/start" --instance "$invalid_long_instance" 2>&1)"; then
  echo "Expected start to reject an instance longer than 123 characters" >&2
  exit 1
fi
assert_contains "$long_start_output" "instance must be at most 123 characters"

if long_dev_output="$("$TMP_DIR/dev" --instance "$invalid_long_instance" project 2>&1)"; then
  echo "Expected dev to reject an instance longer than 123 characters" >&2
  exit 1
fi
assert_contains "$long_dev_output" "instance must be at most 123 characters"

dev_output="$("$TMP_DIR/dev" --instance work project)"
assert_contains "$dev_output" "Connecting to tester@localhost:2223 (work)..."
assert_contains "$dev_output" "GH_TOKEN=work-token"
assert_contains "$dev_output" "-c $TMP_DIR/project"

completion_output="$("$TMP_DIR/dev" --instance work --init)"
assert_contains "$completion_output" "'1:session: _alternative"
assert_contains "$completion_output" "\"dirs:directory: _path_files -/ -W $TMP_DIR\""
