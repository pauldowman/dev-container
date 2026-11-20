#!/usr/bin/env bash
set -euo pipefail

# Runs the container-side client and the host runner against each other. The
# "container" sees CODE_DIR as a symlink to the real code directory, standing in
# for the /Users -> /home link, and a stub docker records what the host ran.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
client_pid=""
trap '[[ -n "$client_pid" ]] && kill "$client_pid" 2>/dev/null; rm -rf "$TMP_DIR"' EXIT
unset GH_TOKEN COMPOSE_FILE DANGEROUSLY_MOUNT_DOCKER_SOCKET INSTANCE DOCKER_HOST DOCKER_CONTEXT DOCKER_BUILDKIT

REPO="$TMP_DIR/repo"
CODE="$TMP_DIR/code"
HOST_CODE="$TMP_DIR/hostcode"
JOBS="$REPO/data/work/docker-bridge"
PROJECT="$CODE/project"
STUB="$TMP_DIR/stub"
CLIENT="$ROOT/scripts/docker-bridge"

fail() {
  echo "$*" >&2
  exit 1
}

assert_equals() {
  [[ "$1" == "$2" ]] || fail "Expected '$2', got '$1'"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "Expected output to contain: $2"$'\n'"$1"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "Expected output not to contain: $2"$'\n'"$1"
}

mkdir -p "$REPO/scripts" "$REPO/config/work" "$REPO/data/work" "$PROJECT" "$TMP_DIR/bin" "$STUB"
ln -s "$CODE" "$HOST_CODE"
cp "$ROOT/docker-bridge" "$ROOT/dev" "$REPO/"
cp "$ROOT/scripts/env.sh" "$REPO/scripts/"
cat > "$REPO/config/work/.env" <<ENV
CODE_DIR=$HOST_CODE
GH_TOKEN=work-token
ENV

cat > "$TMP_DIR/bin/docker" <<STUB
#!/usr/bin/env bash
printf '%s\0' "\$@" > "$STUB/argv"
pwd -P > "$STUB/cwd"
env > "$STUB/env"
cat > "$STUB/stdin"
if [[ -e "$STUB/sleep" ]]; then
  echo \$\$ > "$STUB/started"
  exec sleep 30
fi
[[ -e "$STUB/withdraw" ]] && rm "\$(cat "$STUB/withdraw")"
[[ -e "$STUB/esc" ]] && printf '\033[8mhidden \302\233c \233 \r \342\234\224\n'
echo stub-out
echo stub-err >&2
exit "\$(cat "$STUB/exit" 2>/dev/null || echo 0)"
STUB
chmod +x "$TMP_DIR/bin/docker"

reset() {
  rm -rf "$STUB" "$JOBS"
  mkdir -p "$STUB"
  rm -f "$TMP_DIR"/client.* "$TMP_DIR"/runner.*
}

start_client() {
  local dir="$1"
  shift
  (cd "$dir" && exec env CODE_DIR="$HOST_CODE" DOCKER_BRIDGE_JOBS="$JOBS" "$CLIENT" "$@" \
    >"$TMP_DIR/client.out" 2>"$TMP_DIR/client.err") &
  client_pid=$!
}

finish_client() {
  client_code=0
  wait "$client_pid" || client_code=$?
  client_pid=""
  client_out="$(cat "$TMP_DIR/client.out")"
  client_err="$(cat "$TMP_DIR/client.err")"
}

wait_for_job() {
  local i
  for i in $(seq 100); do
    job="$(find "$JOBS" -name '*.job' 2>/dev/null | head -1 || true)"
    if [[ -n "$job" ]]; then
      job_id="$(basename "$job" .job)"
      return
    fi
    sleep 0.1
  done
  fail "No job appeared; client said: $(cat "$TMP_DIR/client.err")"
}

run_runner() {
  local answers="$1"
  runner_code=0
  printf '%b' "$answers" | env PATH="$TMP_DIR/bin:$PATH" HOST_SECRET=host-secret "$REPO/docker-bridge" work \
    >"$TMP_DIR/runner.out" 2>"$TMP_DIR/runner.err" || runner_code=$?
  runner_out="$(cat "$TMP_DIR/runner.out")"
  runner_err="$(cat "$TMP_DIR/runner.err")"
}

# Runs a client call through the runner; sets client_* and runner_*.
bridge() {
  local answers="$1" dir="$2"
  shift 2
  start_client "$dir" "$@"
  wait_for_job
  run_runner "$answers"
  finish_client
}

stub_argv() {
  tr '\0' '\n' < "$STUB/argv"
}

write_job() {
  job_id="$1"
  shift
  mkdir -p "$JOBS"
  printf '%s\0' "$@" > "$JOBS/$job_id.job"
}

expect_refused() {
  local reason="$1"
  run_runner 'y\n'
  assert_contains "$(cat "$JOBS/$job_id.err")" "$reason"
  assert_equals "$(cat "$JOBS/$job_id.exit")" "125"
  [[ ! -e "$STUB/argv" ]] || fail "docker ran for a refused job"
}

# Paths are translated at component boundaries and arguments reach docker intact.
reset
bridge 'y\nextra\n' "$PROJECT" run -v "$PROJECT/data:/data" --mount "type=bind,src=$CODE/x,dst=/y" \
  "$HOST_CODE/already" "${CODE}x/sibling" "-f$PROJECT/Dockerfile" --label "a b" "it's" "=x" '"q"'
assert_equals "$client_code" "0"
assert_equals "$(cat "$STUB/cwd")" "$PROJECT"
assert_contains "$runner_out" "in   $PROJECT"
assert_equals "$(stub_argv)" "run
-v
$HOST_CODE/project/data:/data
--mount
type=bind,src=$HOST_CODE/x,dst=/y
$HOST_CODE/already
${CODE}x/sibling
-f$HOST_CODE/project/Dockerfile
--label
a b
it's
=x
\"q\""
assert_equals "$(cat "$STUB/stdin")" ""
assert_equals "$client_out" "stub-out"
assert_contains "$client_err" "stub-err"
assert_contains "$client_err" "run ./docker-bridge"
assert_contains "$runner_out" "stub-out"
[[ -z "$(ls -A "$JOBS")" ]] || fail "Client left files behind: $(ls -A "$JOBS")"

# Only DOCKER_*-style and bake variables are forwarded; host and instance secrets are not.
reset
printf 'variable "TAG" {\n  default = "dev"\n}\nvariable "GO_VERSION" {}\nvariable "GOFLAGS" {}\n' > "$PROJECT/docker-bake.hcl"
export DOCKER_BUILDKIT=1 TAG=v1 GO_VERSION=1.24 GOFLAGS=-x DOCKER_HOST=tcp://elsewhere:2375 UNRELATED=x
start_client "$PROJECT" buildx bake
unset DOCKER_BUILDKIT TAG GO_VERSION GOFLAGS DOCKER_HOST UNRELATED
wait_for_job
run_runner 'y\n'
finish_client
rm "$PROJECT/docker-bake.hcl"
stub_env="$(cat "$STUB/env")"
assert_not_contains "$stub_env" "DOCKER_BRIDGE_JOBS="
assert_contains "$stub_env" "DOCKER_BUILDKIT=1"
grep -qx 'TAG=v1' "$STUB/env" || fail "TAG was not forwarded: $stub_env"
grep -qx 'GO_VERSION=1.24' "$STUB/env" || fail "GO_VERSION was not forwarded: $stub_env"
assert_not_contains "$stub_env" "GOFLAGS="
assert_not_contains "$stub_env" "DOCKER_HOST="
assert_not_contains "$stub_env" "UNRELATED="
assert_not_contains "$stub_env" "HOST_SECRET="
assert_not_contains "$stub_env" "work-token"
grep -qx 'BUILDX_GIT_INFO=0' "$STUB/env" || fail "BUILDX_GIT_INFO=0 was not set: $stub_env"

# Variable values holding paths are translated, or refused when the host can't see them.
reset
export COMPOSE_FILE="$PROJECT/compose.yaml"
start_client "$PROJECT" compose up
unset COMPOSE_FILE
wait_for_job
run_runner 'y\n'
finish_client
grep -qx "COMPOSE_FILE=$HOST_CODE/project/compose.yaml" "$STUB/env" || fail "COMPOSE_FILE was not translated: $(cat "$STUB/env")"
reset
export COMPOSE_FILE=/tmp/compose.yaml
start_client "$PROJECT" compose up
unset COMPOSE_FILE
finish_client
assert_equals "$client_code" "125"
assert_contains "$client_err" "COMPOSE_FILE refers to a path"

# The client and the runner agree on which variables a bake job may pass; the
# client also skips a global option's value when looking for bake.
reset
names=(BUILDX_CONFIG BUILDX_GIT_INFO BUILDX_NO_DEFAULT_ATTESTATIONS BUILDX_BAKE_ENTITLEMENTS_FS GIT_DIR
  OTEL_EXPORTER_OTLP_ENDPOINT http_proxy HTTPS_PROXY LC_ALL GODEBUG GO_VERSION DOCKER_TLS DOCKER_CONTENT_TRUST
  SSL_CERT_FILE XDG_CONFIG_HOME TAG DOCKER_BUILDKIT COMPOSE_PROFILES)
for name in "${names[@]}"; do printf 'variable "%s" {}\n' "$name"; done > "$PROJECT/docker-bake.hcl"
for name in "${names[@]}"; do export "$name=C"; done
start_client "$PROJECT" -l debug buildx bake
unset "${names[@]}"
wait_for_job
client_names="$(tr '\0' '\n' < "$job" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=C$/\1/p' | sort)"
kill -HUP "$client_pid"
finish_client
rm "$PROJECT/docker-bake.hcl"
runner_names=""
for name in "${names[@]}"; do
  reset
  write_job 20260101-000000-1 v1 "$HOST_CODE/project" "$name=v" -- buildx bake
  run_runner 'n\n'
  [[ "$(cat "$JOBS/$job_id.err")" == *"may not set"* ]] || runner_names+="$name"$'\n'
done
assert_equals "$client_names" "$(printf '%s' "$runner_names" | sort)"
[[ "$client_names" == *TAG* ]] || fail "The client did not treat -l debug buildx bake as bake"
for bake_command in "buildx --builder b bake" "builder -D bake" "bake"; do
  reset
  echo 'variable "TAG" {}' > "$PROJECT/docker-bake.hcl"
  read -ra bake_args <<< "$bake_command"
  export TAG=v1
  start_client "$PROJECT" "${bake_args[@]}"
  unset TAG
  wait_for_job
  tr '\0' '\n' < "$job" | grep -qx 'TAG=v1' || fail "The client did not treat $bake_command as bake"
  kill -HUP "$client_pid"
  finish_client
  rm "$PROJECT/docker-bake.hcl"
  write_job 20260101-000000-1 v1 "$HOST_CODE/project" TAG=v1 -- "${bake_args[@]}"
  run_runner 'n\n'
  assert_contains "$(cat "$JOBS/$job_id.err")" "declined"
done

# The exit code is propagated.
reset
echo 3 > "$STUB/exit"
bridge 'y\n' "$PROJECT" ps
assert_equals "$client_code" "3"
assert_contains "$runner_err" "exited with 3"

# Declining tells the client.
reset
bridge 'n\n' "$PROJECT" ps
assert_equals "$client_code" "125"
assert_contains "$client_err" "declined on the host"
[[ ! -e "$STUB/argv" ]] || fail "docker ran for a declined job"

# The client refuses what the host cannot see, without queuing a job.
reset
for case in "$TMP_DIR|ps|is not visible on the host" "$PROJECT|run -v /tmp/x:/x img|refers to a path" \
  "$PROJECT|run -v /home/other/x:/x img|refers to a path"; do
  IFS='|' read -r dir arg_line message <<< "$case"
  read -ra args <<< "$arg_line"
  start_client "$dir" "${args[@]}"
  finish_client
  assert_equals "$client_code" "125"
  assert_contains "$client_err" "$message"
  [[ -z "$(ls -A "$JOBS" 2>/dev/null)" ]] || fail "A job was queued for $case"
done
(cd "$PROJECT" && unset CODE_DIR && "$CLIENT" ps 2>"$TMP_DIR/client.err") && fail "Client ran without CODE_DIR" || true
assert_contains "$(cat "$TMP_DIR/client.err")" "CODE_DIR is not set"

# Hand-written jobs that the runner must refuse.
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- run $'\e[8mhidden'
expect_refused "printable ASCII"
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- run $'two\nlines'
expect_refused "printable ASCII"
reset
write_job 20260101-000000-2 v1 "$HOST_CODE/project" SSH_AUTH_SOCK=/x -- buildx bake
expect_refused "may not set SSH_AUTH_SOCK"
reset
write_job 20260101-000000-2 v1 "$HOST_CODE/project" TAG=v1 -- build .
expect_refused "may not set TAG"
reset
write_job 20260101-000000-2 v1 "$HOST_CODE/project" TAG=v1 -- run --label bake img
expect_refused "may not set TAG"
reset
write_job 20260101-000000-2 v1 "$HOST_CODE/project" DOCKER_HOST=tcp://x -- ps
expect_refused "may not set DOCKER_HOST"
reset
write_job 20260101-000000-3 v1 "$HOST_CODE/project" PATH=/x -- ps
expect_refused "may not set PATH"
reset
write_job 20260101-000000-4 v1 "$HOST_CODE/project" -- --config /x ps
expect_refused "global option --config"
reset
write_job 20260101-000000-5 v1 "$HOST_CODE/project" -- -Hunix:///x ps
expect_refused "global option -Hunix"
reset
write_job 20260101-000000-5 v1 "$HOST_CODE/project" -- -DH unix:///x ps
expect_refused "global option -DH"
reset
write_job 20260101-000000-5 v1 "$HOST_CODE/project" -- -Dc evil ps
expect_refused "global option -Dc"
reset
write_job 20260101-000000-5 v1 "$HOST_CODE/project" -- -D -l debug -H unix:///x ps
expect_refused "global option -H"
reset
ln -s "$TMP_DIR" "$PROJECT/escape"
write_job 20260101-000000-6 v1 "$HOST_CODE/project/escape" -- ps
expect_refused "outside $CODE"
rm "$PROJECT/escape"
reset
printf 'v1\0%s\0--\0ps\0' "$HOST_CODE/project" > "$TMP_DIR/real.job"
mkdir -p "$JOBS"
ln -s "$TMP_DIR/real.job" "$JOBS/20260101-000000-7.job"
job_id=20260101-000000-7
expect_refused "not a regular file"

# Planted result symlinks are replaced, not written through.
reset
mkdir -p "$TMP_DIR/victim-dir"
echo original > "$TMP_DIR/victim-file"
start_client "$PROJECT" ps
wait_for_job
ln -s "$TMP_DIR/victim-dir" "$JOBS/$job_id.out"
ln -s "$TMP_DIR/victim-file" "$JOBS/$job_id.err"
run_runner 'y\n'
finish_client
assert_equals "$client_out" "stub-out"
assert_equals "$(ls -A "$TMP_DIR/victim-dir")" ""
assert_equals "$(cat "$TMP_DIR/victim-file")" "original"
reset
start_client "$PROJECT" ps
wait_for_job
ln -s "$TMP_DIR/nowhere" "$JOBS/$job_id.out"
run_runner 'y\n'
finish_client
assert_equals "$client_out" "stub-out"
[[ ! -e "$TMP_DIR/nowhere" ]] || fail "The runner wrote through a dangling symlink"

# A jobs directory that is a symlink is refused.
reset
mkdir -p "$TMP_DIR/elsewhere"
ln -s "$TMP_DIR/elsewhere" "$JOBS"
run_runner 'y\n'
assert_equals "$runner_code" "1"
assert_contains "$runner_err" "is not a real directory"
rm "$JOBS"

# Results left by a client that gave up, and temp files of an interrupted
# runner, are removed; a directory the container put there doesn't stop it.
reset
mkdir -p "$JOBS/20260101-000000-9.out"
echo 0 > "$JOBS/20260101-000000-8.exit"
echo out > "$JOBS/20260101-000000-8.out"
touch "$JOBS/.20260101-000000-8.err.0123456789abcdef.tmp"
run_runner ''
assert_contains "$runner_out" "No pending docker jobs for work."
assert_equals "$(ls -A "$JOBS")" "20260101-000000-9.out"

# Only one runner handles an instance's jobs at a time.
reset
mkdir -p "$JOBS"
python3 -c 'import fcntl, os, sys, time
fcntl.flock(os.open(sys.argv[1], os.O_RDONLY), fcntl.LOCK_EX)
print("locked", flush=True)
time.sleep(30)' "$JOBS" > "$TMP_DIR/lock.out" &
lock_pid=$!
until [[ -s "$TMP_DIR/lock.out" ]]; do sleep 0.1; done
run_runner ''
kill "$lock_pid"
assert_equals "$runner_code" "1"
assert_contains "$runner_err" "already handling jobs for work"

# A host without docker reports 127, and a relative PATH entry does not find a
# docker the container placed in the working directory.
reset
mkdir -p "$TMP_DIR/minbin"
for tool in dirname readlink; do ln -sf "$(command -v "$tool")" "$TMP_DIR/minbin/$tool"; done
printf '#!/bin/sh\ntouch "%s"\n' "$STUB/planted-ran" > "$PROJECT/docker"
chmod +x "$PROJECT/docker"
start_client "$PROJECT" ps
wait_for_job
printf 'y\n' | env PATH=".:$TMP_DIR/minbin" "$(command -v python3)" "$REPO/docker-bridge" work >/dev/null 2>&1
finish_client
rm "$PROJECT/docker"
assert_equals "$client_code" "127"
assert_contains "$client_err" "docker is not on the host PATH"
[[ ! -e "$STUB/planted-ran" ]] || fail "The runner ran a docker from the working directory"

# Ctrl-C in the runner stops docker and tells the client. Job control keeps
# SIGINT from being ignored in the background runner.
reset
touch "$STUB/sleep"
start_client "$PROJECT" run img
wait_for_job
set -m
printf 'y\n' | env PATH="$TMP_DIR/bin:$PATH" "$REPO/docker-bridge" work >/dev/null 2>&1 &
runner_pid=$!
set +m
until [[ -s "$STUB/started" ]]; do sleep 0.1; done
interrupted_at=$SECONDS
kill -INT "$runner_pid"
wait "$runner_pid" || true
(( SECONDS - interrupted_at < 5 )) || fail "The runner did not stop docker promptly"
! kill -0 "$(cat "$STUB/started")" 2>/dev/null || fail "docker is still running"
finish_client
assert_equals "$client_code" "130"

# Only commands that act on the daemon and the job's files are allowed.
for command in "context use x" "-D context ls" "login -u a -p b" "logout" "trust key generate k" "pass run x" \
  "extension install x" "buildx create --use" "buildx --builder b use x" "buildx --builder=b use x" "buildx -D use x" \
  "buildx install" "builder use b" "builder create --use" "builder rm b"; do
  reset
  read -ra command_args <<< "$command"
  write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- "${command_args[@]}"
  expect_refused "is not allowed through the bridge"
done
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- buildx -- x use
expect_refused "buildx option --"
for command in "buildx --builder -- build use x" "builder --builder --builder build use" "-l -- use"; do
  reset
  read -ra command_args <<< "$command"
  write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- "${command_args[@]}"
  expect_refused "may not start with '-'"
done
for command in "buildx build -t use ." "buildx ls" "buildx bake" "buildx --builder b build ." "builder prune" "--version" \
  "compose up -d" "run --rm img"; do
  reset
  read -ra command_args <<< "$command"
  write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- "${command_args[@]}"
  run_runner 'y\n'
  assert_equals "$(cat "$JOBS/$job_id.exit")" "0"
done

# The reviewer sees where the job really runs.
reset
mkdir -p "$CODE/other"
ln -s "$CODE/other" "$PROJECT/link"
write_job 20260101-000000-1 v1 "$HOST_CODE/project/link" -- ps
run_runner 'n\n'
assert_contains "$runner_out" "in   $CODE/other"
rm "$PROJECT/link"

# Special and oversized job files are refused.
reset
mkdir -p "$JOBS"
mkfifo "$JOBS/20260101-000000-1.job"
job_id=20260101-000000-1
expect_refused "not a regular file"
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- run "$(head -c 70000 /dev/zero | tr '\0' x)"
expect_refused "larger than"

# A job ID on the command line handles only that job.
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- ps
write_job 20260101-000000-2 v1 "$HOST_CODE/project" -- images
printf 'y\n' | env PATH="$TMP_DIR/bin:$PATH" "$REPO/docker-bridge" work 20260101-000000-2 >/dev/null 2>&1
assert_equals "$(stub_argv)" "images"
[[ ! -e "$JOBS/20260101-000000-1.exit" ]] || fail "The other job was handled"
run_runner ''
[[ "$runner_code" == 0 ]] || fail "runner failed"
printf 'y\n' | env PATH="$TMP_DIR/bin:$PATH" "$REPO/docker-bridge" work 20260101-000000-9 >/dev/null 2>"$TMP_DIR/runner.err" && fail "A job that isn't pending was accepted" || true
assert_contains "$(cat "$TMP_DIR/runner.err")" "no pending job 20260101-000000-9"

# A job withdrawn after the runner listed it is skipped, not refused.
reset
write_job 20260101-000000-1 v1 "$HOST_CODE/project" -- ps
write_job 20260101-000000-2 v1 "$HOST_CODE/project" -- images
echo "$JOBS/20260101-000000-2.job" > "$STUB/withdraw"
run_runner 'y\ny\n'
assert_contains "$runner_err" "job 20260101-000000-2 was withdrawn"
[[ ! -e "$JOBS/20260101-000000-2.exit" && ! -e "$JOBS/20260101-000000-2.err" ]] || fail "Results were written for a withdrawn job"

# Control characters in docker's output are escaped for the reviewer but reach the container unchanged.
reset
touch "$STUB/esc"
bridge 'y\n' "$PROJECT" ps
assert_contains "$runner_out" '\x1b[8mhidden \x9bc \x9b \x0d ✔'
[[ "$runner_out" != *$'\e'* && "$runner_out" != *$'\r'* ]] || fail "A raw control character reached the reviewer's terminal"
[[ "$client_out" == *$'\e[8mhidden'* ]] || fail "The container did not get docker's raw output"

# A client that hangs up removes its job.
reset
start_client "$PROJECT" ps
wait_for_job
kill -HUP "$client_pid"
finish_client
assert_equals "$client_code" "130"
[[ -z "$(ls -A "$JOBS")" ]] || fail "The job was left behind: $(ls -A "$JOBS")"

echo "docker-bridge tests passed"
