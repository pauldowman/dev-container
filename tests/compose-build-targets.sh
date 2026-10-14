#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
touch "$TMP_DIR/empty.env"

fail() {
  echo "$*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"

  [[ "$output" == *"$expected"* ]] || fail "Expected rendered Compose configuration to contain: $expected"
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"

  [[ "$output" != *"$unexpected"* ]] || fail "Expected rendered Compose configuration not to contain: $unexpected"
}

compose_files=(-f "$ROOT/docker-compose.yml")

render_compose() {
  env -u BUILD_TARGET -u DOCKERFILE \
    INSTANCE=main \
    CODE_DIR=/tmp/code \
    DOTFILES_INSTALL_CMD="${DOTFILES_INSTALL_CMD-}" \
    DOTFILES_REPO="${DOTFILES_REPO-}" \
    SSH_AUTHORIZED_KEYS=test-key \
    USERNAME="${USERNAME-tester}" \
    "$@" \
    docker compose --env-file "$TMP_DIR/empty.env" "${compose_files[@]}" config
}

default_config="$(render_compose)"
assert_contains "$default_config" "dockerfile: Dockerfile"
assert_contains "$default_config" "target: base"
assert_contains "$default_config" "image: dev-container:main-base"
assert_contains "$default_config" "instance-install: $ROOT/config/main/install"
assert_not_contains "$default_config" "DEV_CONTAINER_REPO_DIR"
assert_contains "$default_config" "source: $ROOT/data/main"
assert_contains "$default_config" "target: /var/lib/dev-container/data"
assert_not_contains "$default_config" "ca-certificates"
assert_contains "$default_config" "source: /tmp/code"
assert_contains "$default_config" "target: /tmp/code"
assert_not_contains "$default_config" "/home/tester"
assert_not_contains "$default_config" "source: home"
assert_contains "$default_config" 'shm_size: "1073741824"'
assert_not_contains "$default_config" "/var/run/docker.sock"

docker_socket_config="$(compose_files+=(-f "$ROOT/docker-compose.docker-socket.yml"); render_compose)"
assert_contains "$docker_socket_config" "source: /var/run/docker.sock"
assert_contains "$docker_socket_config" "target: /var/run/docker.sock"
assert_contains "$docker_socket_config" "target: /tmp/code"

gui_config="$(render_compose BUILD_TARGET=gui)"
assert_contains "$gui_config" "target: gui"
assert_contains "$gui_config" "image: dev-container:main-gui"

work_base_config="$(render_compose INSTANCE=work BUILD_TARGET=base)"
assert_contains "$work_base_config" "image: dev-container:work-base"
assert_contains "$work_base_config" "source: $ROOT/data/work"

work_gui_config="$(render_compose INSTANCE=work BUILD_TARGET=gui)"
assert_contains "$work_gui_config" "image: dev-container:work-gui"

personal_base_config="$(render_compose INSTANCE=personal BUILD_TARGET=base)"
assert_contains "$personal_base_config" "image: dev-container:personal-base"
assert_contains "$personal_base_config" "source: $ROOT/data/personal"

argument_config="$(USERNAME=alice DOTFILES_REPO=https://example.test/dotfiles.git DOTFILES_INSTALL_CMD=setup.sh render_compose)"
assert_contains "$argument_config" "USERNAME: alice"
assert_contains "$argument_config" "DOTFILES_REPO: https://example.test/dotfiles.git"
assert_contains "$argument_config" "DOTFILES_INSTALL_CMD: setup.sh"

if missing_instance_output="$(env -u INSTANCE CODE_DIR=/tmp/code docker compose --env-file "$TMP_DIR/empty.env" -f "$ROOT/docker-compose.yml" config 2>&1)"; then
  fail "Expected rendering without INSTANCE to fail"
fi
assert_contains "$missing_instance_output" "Pass the instance name"

fixture_repo="$TMP_DIR/repo"
mkdir -p "$fixture_repo/config/work"
cp "$ROOT/docker-compose.yml" "$fixture_repo/"
printf 'USERNAME=from-root-env\n' > "$fixture_repo/.env"
cat > "$fixture_repo/docker-compose.override.yml" <<'YAML'
services:
  dev-container:
    volumes:
      - /root-override:/root-override
YAML
printf 'CODE_DIR=/tmp/code\n' > "$fixture_repo/config/work/.env"
cat > "$fixture_repo/config/work/docker-compose.override.yml" <<'YAML'
services:
  dev-container:
    volumes:
      - /instance-override:/instance-override
YAML

helper_config="$(cd "$fixture_repo" && env -u USERNAME -u INSTANCE -u COMPOSE_FILE SSH_AUTHORIZED_KEYS=test-key \
  bash -c 'SCRIPT_DIR="$PWD"; source "$1"; select_instance work; set_compose_args; docker compose "${COMPOSE_ARGS[@]}" config' _ "$ROOT/scripts/env.sh")"
assert_contains "$helper_config" "source: /instance-override"
assert_not_contains "$helper_config" "/root-override"
assert_not_contains "$helper_config" "from-root-env"
assert_contains "$helper_config" "instance-install: $fixture_repo/config/work/install"

check_rendered() {
  local code_dir="$1"
  shift

  env -u BUILD_TARGET -u DOCKERFILE INSTANCE=main CODE_DIR="$code_dir" SSH_AUTHORIZED_KEYS=test-key \
    docker compose --env-file "$TMP_DIR/empty.env" "$@" config --format json |
    "$ROOT/scripts/check-repo-mounts" compose "$ROOT" "$ROOT/data/main"
}

override_file="$TMP_DIR/override.yml"
cat > "$override_file" <<'YAML'
services:
  dev-container:
    volumes:
      - /instance-override:/instance-override
YAML

check_rendered /tmp/code -f "$ROOT/docker-compose.yml" || fail "Expected the base configuration to pass the repository mount check"
check_rendered /tmp/code -f "$ROOT/docker-compose.yml" -f "$override_file" || fail "Expected an unrelated override mount to pass the repository mount check"
check_rendered /tmp/code -f "$ROOT/docker-compose.yml" -f "$ROOT/docker-compose.docker-socket.yml" || fail "Expected the Docker socket mount to pass the repository mount check"
if check_rendered "$(dirname "$ROOT")" -f "$ROOT/docker-compose.yml" 2>/dev/null; then
  fail "Expected a CODE_DIR containing the repository to fail the repository mount check"
fi
