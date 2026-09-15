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

render_compose() {
  env -u BUILD_TARGET -u DOCKERFILE -u INSTANCE \
    CODE_DIR=/tmp/code \
    DEV_CONTAINER_REPO_DIR=/tmp/code/dev-container \
    DOTFILES_INSTALL_CMD="${DOTFILES_INSTALL_CMD-}" \
    DOTFILES_REPO="${DOTFILES_REPO-}" \
    SSH_AUTHORIZED_KEYS=test-key \
    USERNAME="${USERNAME-tester}" \
    "$@" \
    docker compose --env-file "$TMP_DIR/empty.env" -f "$ROOT/docker-compose.yml" config
}

default_config="$(render_compose)"
assert_contains "$default_config" "dockerfile: Dockerfile"
assert_contains "$default_config" "target: base"
assert_contains "$default_config" "image: dev-container:dev-container-base"
assert_contains "$default_config" "DEV_CONTAINER_REPO_DIR: /tmp/code/dev-container"
assert_contains "$default_config" "source: /tmp/code"
assert_contains "$default_config" "target: /tmp/code"
assert_not_contains "$default_config" "/home/tester"
assert_not_contains "$default_config" "source: home"

gui_config="$(render_compose BUILD_TARGET=gui)"
assert_contains "$gui_config" "target: gui"
assert_contains "$gui_config" "image: dev-container:dev-container-gui"

work_base_config="$(render_compose INSTANCE=work BUILD_TARGET=base)"
assert_contains "$work_base_config" "image: dev-container:work-base"
assert_contains "$work_base_config" "DEV_CONTAINER_REPO_DIR: /tmp/code/dev-container"

work_gui_config="$(render_compose INSTANCE=work BUILD_TARGET=gui)"
assert_contains "$work_gui_config" "image: dev-container:work-gui"

personal_base_config="$(render_compose INSTANCE=personal BUILD_TARGET=base)"
assert_contains "$personal_base_config" "image: dev-container:personal-base"
assert_contains "$personal_base_config" "DEV_CONTAINER_REPO_DIR: /tmp/code/dev-container"

argument_config="$(USERNAME=alice DOTFILES_REPO=https://example.test/dotfiles.git DOTFILES_INSTALL_CMD=setup.sh render_compose)"
assert_contains "$argument_config" "USERNAME: alice"
assert_contains "$argument_config" "DOTFILES_REPO: https://example.test/dotfiles.git"
assert_contains "$argument_config" "DOTFILES_INSTALL_CMD: setup.sh"
