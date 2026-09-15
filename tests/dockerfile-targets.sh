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

if [[ "${1:-}" == "--build" ]]; then
  for target in base-target-test gui-target-test; do
    docker build \
      --build-arg USERNAME="${USER:-tester}" \
      --output type=cacheonly \
      --target "$target" \
      "$ROOT"
  done
fi
