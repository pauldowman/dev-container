#!/usr/bin/env bash
set -euo pipefail

# Runs dev's first-connect remote command for real: the ssh stub executes it
# locally with a temporary HOME, and SHELL=bash reads a fixture .bash_profile.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unset GH_TOKEN COMPOSE_FILE DANGEROUSLY_MOUNT_DOCKER_SOCKET INSTANCE

fail() {
  echo "$*" >&2
  exit 1
}

mkdir -p "$TMP_DIR/repo/scripts" "$TMP_DIR/repo/config/work" "$TMP_DIR/bin" "$TMP_DIR/remote-home"
cp "$ROOT/dev" "$TMP_DIR/repo/"
cp "$ROOT/scripts/env.sh" "$TMP_DIR/repo/scripts/"
cat > "$TMP_DIR/repo/config/work/.env" <<ENV
CODE_DIR=$TMP_DIR
USERNAME=tester
GH_TOKEN=work-token
ENV
printf 'export FROM_SHELL_RC=rc-value\n' > "$TMP_DIR/remote-home/.bash_profile"

cat > "$TMP_DIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "0.0.0.0:2222"
STUB
cat > "$TMP_DIR/bin/ssh-add" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$TMP_DIR/bin/ssh" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 0 && "$1" != "localhost" ]]; do
  shift
done
shift
if [[ "$*" == *"tmux new-session"* ]]; then
  echo "tmux attached"
  exit 0
fi
HOME="$REMOTE_HOME" SHELL=/bin/bash exec bash -c "$*"
STUB
chmod +x "$TMP_DIR/bin/"*

export PATH="$TMP_DIR/bin:$PATH" REMOTE_HOME="$TMP_DIR/remote-home" SSH_AUTH_SOCK=/tmp/fake-ssh-agent.sock
script="$TMP_DIR/repo/config/work/first-connect.sh"
marker="$TMP_DIR/remote-home/.cache/dev-container/first-connect.done"
runs="$TMP_DIR/runs"

cat > "$script" <<SCRIPT
echo "run GH_TOKEN=\$GH_TOKEN FROM_SHELL_RC=\${FROM_SHELL_RC:-}" >> "$runs"
[ ! -e "$TMP_DIR/fail" ]
SCRIPT

connect() {
  "$TMP_DIR/repo/dev" work project 2>&1
}

touch "$TMP_DIR/fail"
output="$(connect)"
[[ "$output" == *"did not complete; it will run again on the next connect"* ]] || fail "Expected a failure warning: $output"
[[ "$output" == *"tmux attached"* ]] || fail "Expected dev to attach after a failed first-connect script"
[[ ! -e "$marker" ]] || fail "A failed first-connect script must not create the marker"
[[ "$(wc -l < "$runs")" -eq 1 ]] || fail "Expected one run after the failure"

rm "$TMP_DIR/fail"
output="$(connect)"
[[ "$output" == *"tmux attached"* ]] || fail "Expected dev to attach: $output"
[[ -e "$marker" ]] || fail "A successful first-connect script must create the marker"
[[ "$(tail -n 1 "$runs")" == "run GH_TOKEN=work-token FROM_SHELL_RC=rc-value" ]] || fail "Unexpected script environment: $(tail -n 1 "$runs")"

connect >/dev/null
[[ "$(wc -l < "$runs")" -eq 2 ]] || fail "The first-connect script must not rerun once the marker exists"

rm "$marker"
mkdir -p "$TMP_DIR/remote-home/.cache/dev-container"
exec 9>"$TMP_DIR/remote-home/.cache/dev-container/first-connect.lock"
flock 9
output="$(connect)"
exec 9>&-
[[ "$output" == *"already running in another session; skipping"* ]] || fail "Expected a held lock to skip the run: $output"
[[ "$(wc -l < "$runs")" -eq 2 ]] || fail "A held lock must skip the run"
[[ ! -e "$marker" ]] || fail "A skipped run must not create the marker"
