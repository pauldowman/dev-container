#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "$*" >&2
  exit 1
}

expected_command="$HOME/.local/bin/codex"
standalone_root="$HOME/.codex/packages/standalone"
resolved_command="$(zsh -c 'command -v codex')"

[[ "$resolved_command" == "$expected_command" ]] || fail "Expected codex to resolve to $expected_command, got $resolved_command"
zsh -ic 'test "$(command -v codex)" = "$HOME/.local/bin/codex"'
[[ -L "$expected_command" ]] || fail "Expected the standalone codex command to be a symlink"
standalone_target="$(readlink -f -- "$expected_command")"
[[ "$standalone_target" == "$standalone_root/"* ]] || fail "Codex target is outside the standalone package: $standalone_target"
[[ -O "$standalone_target" && -w "$standalone_target" ]] || fail "Codex standalone target is not user-owned and writable"
[[ -O "$standalone_root" && -w "$standalone_root" ]] || fail "Codex standalone package root is not user-owned and writable"
[[ -z "$(find "$standalone_root" ! -user "$(id -un)" -print -quit)" ]] || fail "Codex standalone package contains files owned by another user"
"$expected_command" --version >/dev/null

[[ "$(npm prefix -g)" == "/usr/local" ]] || fail "npm global prefix changed from /usr/local"
npm_root="$(npm root -g)"
[[ ! -e "$npm_root/@openai/codex" ]] || fail "Found a system npm installation of @openai/codex"
[[ ! -e "$HOME/.local/lib/node_modules/@openai/codex" ]] || fail "Found a user-prefix npm installation of @openai/codex"

if [[ -n "${PERSISTED_MARKER_SOURCE:-}" ]]; then
  marker="$HOME/.codex/persisted-marker"
  [[ -L "$marker" ]] || fail "Persisted Codex-adjacent marker is not linked"
  [[ "$(readlink -- "$marker")" == "$PERSISTED_MARKER_SOURCE" ]] || fail "Persisted marker points to the wrong source"
  [[ "$(cat "$marker")" == "persisted" ]] || fail "Persisted marker content is unavailable"
  [[ -d "$standalone_root" && -x "$standalone_target" ]] || fail "Persisted marker replaced the standalone package"
fi
