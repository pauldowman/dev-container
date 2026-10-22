#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "$ROOT/.home-lifecycle.XXXXXX")"
LINK_HOME="$ROOT/scripts/link-home"
CONTAINER_PREFIX="home-lifecycle-$$-$RANDOM"
DATA_MOUNT=/var/lib/dev-container/data
containers=()

cleanup() {
  local container

  for container in "${containers[@]}"; do
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

start_container() {
  local name="$1"
  local instance="$2"

  containers+=("$name")
  docker run -d \
    --name "$name" \
    --env FIXTURE_ROOT="$FIXTURE_ROOT" \
    --env DATA_MOUNT="$DATA_MOUNT" \
    --volume "$LINK_HOME:/usr/local/bin/link-home:ro" \
    --volume "$FIXTURE_ROOT/code:$FIXTURE_ROOT/code" \
    --volume "$FIXTURE_ROOT/data/$instance:$DATA_MOUNT" \
    ubuntu:26.10 sleep infinity >/dev/null
}

link_home() {
  docker exec "$1" bash -ceu '
    mkdir -p /home/tester
    /usr/local/bin/link-home "$DATA_MOUNT/home" "$DATA_MOUNT/persist" /home/tester
  '
}

for instance in work personal; do
  mkdir -p "$FIXTURE_ROOT/data/$instance/home/.config/tool"
  printf '%s\n' "$instance" > "$FIXTURE_ROOT/data/$instance/home/.config/tool/state"
  printf '.config/tool/state\n' > "$FIXTURE_ROOT/data/$instance/persist"
done
mkdir -p "$FIXTURE_ROOT/code/project"
printf 'code\n' > "$FIXTURE_ROOT/code/project/marker"

first="$CONTAINER_PREFIX-first"
start_container "$first" work
docker exec "$first" bash -ceu 'mkdir -p /home/tester && printf "ephemeral\n" > /home/tester/unlisted-marker'
link_home "$first"
docker exec "$first" bash -ceu '
  test "$(cat /home/tester/.config/tool/state)" = work
  test "$(cat "$FIXTURE_ROOT/code/project/marker")" = code
'
docker rm -f "$first" >/dev/null

second="$CONTAINER_PREFIX-second"
third="$CONTAINER_PREFIX-third"
other="$CONTAINER_PREFIX-other"
start_container "$second" work
start_container "$third" work
start_container "$other" personal

for container in "$second" "$third"; do
  docker exec "$container" bash -ceu 'mkdir -p /home/tester && test ! -e /home/tester/unlisted-marker'
  link_home "$container"
  docker exec "$container" bash -ceu '
    test "$(cat /home/tester/.config/tool/state)" = work
    test "$(cat "$FIXTURE_ROOT/code/project/marker")" = code
  '
done
link_home "$other"

docker exec "$second" bash -ceu 'printf "shared\n" > /home/tester/.config/tool/state'
[[ "$(docker exec "$third" cat /home/tester/.config/tool/state)" == "shared" ]]
[[ "$(cat "$FIXTURE_ROOT/data/work/home/.config/tool/state")" == "shared" ]]
[[ "$(docker exec "$other" cat /home/tester/.config/tool/state)" == "personal" ]]
docker exec "$other" bash -ceu 'test ! -e "$FIXTURE_ROOT/data"'
