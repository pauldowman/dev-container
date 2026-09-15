#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "$ROOT/.home-lifecycle.XXXXXX")"
PERSISTENT_HOME="$FIXTURE_ROOT/data/home"
LINK_HOME="$ROOT/scripts/link-home"
CONTAINER_PREFIX="home-lifecycle-$$-$RANDOM"
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

  containers+=("$name")
  docker run -d \
    --name "$name" \
    --env FIXTURE_ROOT="$FIXTURE_ROOT" \
    --env PERSISTENT_HOME="$PERSISTENT_HOME" \
    --volume "$LINK_HOME:/usr/local/bin/link-home:ro" \
    --volume "$FIXTURE_ROOT:$FIXTURE_ROOT" \
    ubuntu:24.04 sleep infinity >/dev/null
}

mkdir -p "$PERSISTENT_HOME/.config/tool" "$FIXTURE_ROOT/code/project"
printf 'persistent\n' > "$PERSISTENT_HOME/.config/tool/state"
printf 'code\n' > "$FIXTURE_ROOT/code/project/marker"

first="$CONTAINER_PREFIX-first"
start_container "$first"
docker exec "$first" bash -ceu '
  mkdir -p /home/tester
  printf "ephemeral\n" > /home/tester/unlisted-marker
  /usr/local/bin/link-home "$PERSISTENT_HOME" /home/tester
  test "$(cat /home/tester/.config/tool/state)" = persistent
  test "$(cat "$FIXTURE_ROOT/code/project/marker")" = code
'
docker rm -f "$first" >/dev/null

second="$CONTAINER_PREFIX-second"
third="$CONTAINER_PREFIX-third"
start_container "$second"
start_container "$third"

for container in "$second" "$third"; do
  docker exec "$container" bash -ceu '
    mkdir -p /home/tester
    test ! -e /home/tester/unlisted-marker
    /usr/local/bin/link-home "$PERSISTENT_HOME" /home/tester
    test "$(cat /home/tester/.config/tool/state)" = persistent
    test "$(cat "$FIXTURE_ROOT/code/project/marker")" = code
  '
done

docker exec "$second" bash -ceu 'printf "shared\n" > /home/tester/.config/tool/state'
[[ "$(docker exec "$third" cat /home/tester/.config/tool/state)" == "shared" ]]
[[ "$(cat "$PERSISTENT_HOME/.config/tool/state")" == "shared" ]]
