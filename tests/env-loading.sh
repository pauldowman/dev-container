#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unset BUILD_TARGET DOCKERFILE COMPOSE_FILE DANGEROUSLY_MOUNT_DOCKER_SOCKET INSTANCE GH_TOKEN SSH_PORT CODE_DIR USERNAME

copy_runtime() {
  mkdir -p "$TMP_DIR/scripts" "$TMP_DIR/bin"
  cp "$ROOT/build" "$ROOT/start" "$ROOT/dev" "$TMP_DIR/"
  cp "$ROOT/scripts/env.sh" "$TMP_DIR/scripts/"
}

write_stubs() {
  cat > "$TMP_DIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMP_DIR/docker.log"
if [[ "$*" == *" port dev-container 22"* ]]; then
  echo "0.0.0.0:${SSH_PORT:-2222}"
  exit 0
fi
if [[ "$*" == *" ps -q dev-container"* ]]; then
  [[ -n "${STUB_RUNNING_MOUNTS+x}" ]] && echo "running-container-id"
  exit 0
fi
if [[ "${1:-}" == "inspect" && "$*" == *".Mounts"* ]]; then
  printf '%b' "$STUB_RUNNING_MOUNTS"
  exit 0
fi
if [[ "${1:-}" == "inspect" ]]; then
  [[ -n "${STUB_RUNNING_MOUNTS+x}" ]] && echo "true" || echo "false"
  exit 0
fi
echo "docker INSTANCE=${INSTANCE:-} SSH_PORT=${SSH_PORT:-} CODE_DIR=${CODE_DIR:-} DEV_CONTAINER_REPO_DIR=${DEV_CONTAINER_REPO_DIR:-} BUILD_TARGET=${BUILD_TARGET:-} GH_TOKEN=${GH_TOKEN:-} args=$*"
STUB

  cat > "$TMP_DIR/bin/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh GH_TOKEN=${GH_TOKEN:-} args=$*"
STUB

  cat > "$TMP_DIR/bin/ssh-add" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

  chmod +x "$TMP_DIR/bin/docker" "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/ssh-add"
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

assert_not_contains() {
  local output="$1"
  local unexpected="$2"

  if [[ "$output" == *"$unexpected"* ]]; then
    echo "Expected output not to contain: $unexpected" >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_failure() {
  local expected="$1"
  shift
  local output

  if output="$("$@" 2>&1)"; then
    echo "Expected failure containing '$expected' from: $*" >&2
    exit 1
  fi
  assert_contains "$output" "$expected"
}

write_config() {
  local instance="$1"

  mkdir -p "$TMP_DIR/config/$instance"
  cat > "$TMP_DIR/config/$instance/.env"
}

compose_prefix() {
  local instance="$1"

  printf '%s' "compose -p $instance --env-file $TMP_DIR/config/$instance/.env -f $TMP_DIR/docker-compose.yml"
}

copy_runtime
write_stubs

export TMP_DIR
export PATH="$TMP_DIR/bin:$PATH"
export SSH_AUTH_SOCK=/tmp/fake-ssh-agent.sock

# A root .env from the old layout must be ignored.
cat > "$TMP_DIR/.env" <<'ENV'
SSH_PORT=9999
GH_TOKEN=root-token
ENV

write_config work <<ENV
CODE_DIR=$TMP_DIR
BUILD_TARGET=gui
GH_TOKEN=work-token
INSTANCE=bad/name
SSH_PORT=2223
USERNAME=tester
ENV

write_config scratch <<ENV
CODE_DIR=$TMP_DIR
ENV

for script in build start dev; do
  expect_failure "Usage: $script <instance>" "$TMP_DIR/$script"
  expect_failure "create $TMP_DIR/config/missing/.env" "$TMP_DIR/$script" missing project
done

start_output="$("$TMP_DIR/start" work)"
assert_contains "$start_output" "INSTANCE=work"
assert_contains "$start_output" "SSH_PORT=2223"
assert_contains "$start_output" "CODE_DIR=$TMP_DIR"
assert_contains "$start_output" "DEV_CONTAINER_REPO_DIR=$TMP_DIR"
assert_contains "$start_output" "BUILD_TARGET=gui"
assert_contains "$start_output" "args=$(compose_prefix work) up -d"
[[ -d "$TMP_DIR/config/work/install" ]] || { echo "Expected start to create config/work/install" >&2; exit 1; }

scratch_output="$("$TMP_DIR/start" scratch)"
assert_contains "$scratch_output" "INSTANCE=scratch"
assert_contains "$scratch_output" "SSH_PORT= "
assert_contains "$scratch_output" "BUILD_TARGET=base"
assert_contains "$scratch_output" "GH_TOKEN= "

touch "$TMP_DIR/config/work/docker-compose.override.yml"
override_output="$("$TMP_DIR/start" work)"
assert_contains "$override_output" "args=$(compose_prefix work) -f $TMP_DIR/config/work/docker-compose.override.yml up -d"

write_config docker <<ENV
CODE_DIR=$TMP_DIR
DANGEROUSLY_MOUNT_DOCKER_SOCKET=true
ENV
touch "$TMP_DIR/config/docker/docker-compose.override.yml"
docker_socket_output="$("$TMP_DIR/start" docker)"
assert_contains "$docker_socket_output" "args=$(compose_prefix docker) -f $TMP_DIR/config/docker/docker-compose.override.yml -f $TMP_DIR/docker-compose.docker-socket.yml up -d"

write_config nodocker <<ENV
CODE_DIR=$TMP_DIR
DANGEROUSLY_MOUNT_DOCKER_SOCKET=false
ENV
no_docker_socket_output="$("$TMP_DIR/start" nodocker)"
assert_contains "$no_docker_socket_output" "args=$(compose_prefix nodocker) up -d"

write_config composefile <<ENV
CODE_DIR=$TMP_DIR
COMPOSE_FILE=docker-compose.yml
ENV
for script in build start dev; do
  expect_failure "COMPOSE_FILE is not supported" "$TMP_DIR/$script" composefile project
done

write_config baddocker <<ENV
CODE_DIR=$TMP_DIR
DANGEROUSLY_MOUNT_DOCKER_SOCKET=yes
ENV
expect_failure "DANGEROUSLY_MOUNT_DOCKER_SOCKET must be true or false" "$TMP_DIR/start" baddocker

running_with_socket_output="$(STUB_RUNNING_MOUNTS='/var/run/docker.sock\n' "$TMP_DIR/start" docker)"
assert_not_contains "$running_with_socket_output" " up -d"

STUB_RUNNING_MOUNTS='/tmp/code\n' expect_failure "docker is running with docker.sock mounted=false but DANGEROUSLY_MOUNT_DOCKER_SOCKET=true" "$TMP_DIR/start" docker

running_without_socket_ok_output="$(STUB_RUNNING_MOUNTS='/tmp/code\n' "$TMP_DIR/start" nodocker)"
assert_not_contains "$running_without_socket_ok_output" " up -d"

STUB_RUNNING_MOUNTS='/tmp/code\n/var/run/docker.sock\n' expect_failure "nodocker is running with docker.sock mounted=true but DANGEROUSLY_MOUNT_DOCKER_SOCKET=false; recreate it with ./build nodocker, then ./start nodocker" "$TMP_DIR/start" nodocker

start_override_output="$("$TMP_DIR/start" work --ssh-port 3333)"
assert_contains "$start_override_output" "INSTANCE=work"
assert_contains "$start_override_output" "SSH_PORT=3333"

build_output="$("$TMP_DIR/build" work --progress plain)"
assert_contains "$build_output" "INSTANCE=work"
assert_contains "$build_output" "DEV_CONTAINER_REPO_DIR=$TMP_DIR"
assert_contains "$build_output" "BUILD_TARGET=gui"
assert_contains "$build_output" "args=$(compose_prefix work) -f $TMP_DIR/config/work/docker-compose.override.yml down --remove-orphans"
assert_contains "$build_output" "args=$(compose_prefix work) -f $TMP_DIR/config/work/docker-compose.override.yml build --progress plain"

docker_build_output="$("$TMP_DIR/build" docker)"
assert_contains "$docker_build_output" "args=$(compose_prefix docker) -f $TMP_DIR/config/docker/docker-compose.override.yml -f $TMP_DIR/docker-compose.docker-socket.yml build"

nodocker_build_output="$("$TMP_DIR/build" nodocker)"
assert_contains "$nodocker_build_output" "args=$(compose_prefix nodocker) down --remove-orphans"
assert_contains "$nodocker_build_output" "args=$(compose_prefix nodocker) build"

write_config invalid <<ENV
CODE_DIR=$TMP_DIR
BUILD_TARGET=desktop
ENV
expect_failure "BUILD_TARGET must be base or gui" "$TMP_DIR/build" invalid
expect_failure "BUILD_TARGET must be base or gui" "$TMP_DIR/start" invalid

write_config legacy <<ENV
CODE_DIR=$TMP_DIR
DOCKERFILE=Dockerfile.gui
ENV
expect_failure "DOCKERFILE is obsolete" "$TMP_DIR/build" legacy
expect_failure "DOCKERFILE is obsolete" "$TMP_DIR/start" legacy

mkdir "$TMP_DIR/not-repo-parent"
write_config outside <<ENV
CODE_DIR=$TMP_DIR/not-repo-parent
ENV
expect_failure "repository path must be inside CODE_DIR" "$TMP_DIR/build" outside
expect_failure "repository path must be inside CODE_DIR" "$TMP_DIR/start" outside

write_config relative <<'ENV'
CODE_DIR=.
ENV
expect_failure "CODE_DIR must be an absolute path" "$TMP_DIR/build" relative
expect_failure "CODE_DIR must be an absolute path" "$TMP_DIR/start" relative

ln -s "$TMP_DIR" "$TMP_DIR/code-dir-alias"
write_config symlink <<ENV
CODE_DIR=$TMP_DIR/code-dir-alias
ENV
expect_failure "CODE_DIR must be a canonical path" "$TMP_DIR/build" symlink
expect_failure "CODE_DIR must be a canonical path" "$TMP_DIR/start" symlink

valid_long_instance="$(printf 'a%.0s' {1..123})"
invalid_long_instance="${valid_long_instance}a"
write_config "$valid_long_instance" <<ENV
CODE_DIR=$TMP_DIR
ENV
"$TMP_DIR/build" "$valid_long_instance" >/dev/null
"$TMP_DIR/start" "$valid_long_instance" >/dev/null
for script in build start dev; do
  expect_failure "instance must be at most 123 characters" "$TMP_DIR/$script" "$invalid_long_instance" project
done
expect_failure "instance must start with a lowercase letter or digit" "$TMP_DIR/start" Bad

: > "$TMP_DIR/docker.log"
dev_output="$("$TMP_DIR/dev" work project)"
assert_contains "$dev_output" "Connecting to tester@localhost:2223 (work)..."
assert_contains "$dev_output" "GH_TOKEN=work-token"
assert_contains "$dev_output" "-c $TMP_DIR/project"
assert_contains "$(cat "$TMP_DIR/docker.log")" "$(compose_prefix work) -f $TMP_DIR/config/work/docker-compose.override.yml port dev-container 22"

: > "$TMP_DIR/docker.log"
list_output="$("$TMP_DIR/dev" docker list)"
assert_contains "$list_output" "-p 2222 localhost tmux list-sessions"
assert_not_contains "$list_output" "localhost GH_TOKEN="
assert_contains "$(cat "$TMP_DIR/docker.log")" "$(compose_prefix docker) -f $TMP_DIR/config/docker/docker-compose.override.yml -f $TMP_DIR/docker-compose.docker-socket.yml port dev-container 22"

[[ "$("$TMP_DIR/dev" work --code-dir)" == "$TMP_DIR" ]] || { echo "Expected dev --code-dir to print CODE_DIR" >&2; exit 1; }

completion_output="$("$TMP_DIR/dev" --init)"
assert_contains "$completion_output" "instances=($TMP_DIR/config/*/.env(N:h:t))"
assert_contains "$completion_output" "$TMP_DIR/dev \"\${words[2]}\" --code-dir"
assert_contains "$completion_output" "\"dirs:directory: _path_files -/ -W \${(q)code_dir}\""
