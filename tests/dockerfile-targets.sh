#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_equals() {
  local actual="$1"
  local expected="$2"

  if [[ "$actual" != "$expected" ]]; then
    echo "Expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_equals "$(awk 'toupper($1) == "FROM" { line = $0 } END { print line }' "$ROOT/Dockerfile")" "FROM development AS base"
assert_equals "$(awk 'toupper($1) == "FROM" && tolower($0) ~ / as gui$/ { print $0 }' "$ROOT/Dockerfile")" "FROM development AS gui"
assert_equals "$(awk 'toupper($1) == "FROM" && tolower($0) ~ / as base-target-test$/ { print $0 }' "$ROOT/Dockerfile")" "FROM development AS base-target-test"
assert_equals "$(awk 'toupper($1) == "FROM" && tolower($0) ~ / as gui-target-test$/ { print $0 }' "$ROOT/Dockerfile")" "FROM gui AS gui-target-test"

build_target() {
  local target="$1"
  local install_context="$2"

  docker build \
    --build-arg USERNAME="${USER:-tester}" \
    --build-context instance-install="$install_context" \
    --output type=cacheonly \
    --progress plain \
    --target "$target" \
    "$ROOT"
}

if [[ "${1:-}" == "--build" ]]; then
  INSTALL_FIXTURES="$(mktemp -d)"
  trap 'rm -rf "$INSTALL_FIXTURES"' EXIT
  mkdir -p "$INSTALL_FIXTURES/empty" "$INSTALL_FIXTURES/failing-root" "$INSTALL_FIXTURES/failing-user"
  printf 'echo failing-root-fixture-ran; exit 1\n' > "$INSTALL_FIXTURES/failing-root/custom-install-root.sh"
  printf 'echo failing-user-fixture-ran; exit 1\n' > "$INSTALL_FIXTURES/failing-user/custom-install-user.sh"

  for target in base-target-test gui-target-test; do
    build_target "$target" "$INSTALL_FIXTURES/empty"
  done

  for fixture in failing-root failing-user; do
    if output="$(build_target base-target-test "$INSTALL_FIXTURES/$fixture" 2>&1)"; then
      echo "Expected the build to run and fail on the $fixture install script" >&2
      exit 1
    fi
    if [[ "$output" != *"$fixture-fixture-ran"* ]]; then
      echo "Expected the build to fail because the $fixture install script ran" >&2
      echo "$output" >&2
      exit 1
    fi
  done
fi
