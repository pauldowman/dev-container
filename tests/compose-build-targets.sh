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

render_compose() {
  env -u BUILD_TARGET -u DOCKERFILE \
    CODE_DIR=/tmp/code \
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

gui_config="$(render_compose BUILD_TARGET=gui)"
assert_contains "$gui_config" "target: gui"

argument_config="$(USERNAME=alice DOTFILES_REPO=https://example.test/dotfiles.git DOTFILES_INSTALL_CMD=setup.sh render_compose)"
assert_contains "$argument_config" "USERNAME: alice"
assert_contains "$argument_config" "DOTFILES_REPO: https://example.test/dotfiles.git"
assert_contains "$argument_config" "DOTFILES_INSTALL_CMD: setup.sh"
