#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-repo-mounts"
TMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"

REPO="$TMP_DIR/repo"
ALLOWED="$REPO/data/work"
mkdir -p "$ALLOWED/certs" "$REPO/data/other" "$REPO/scripts" "$REPO/config" "$TMP_DIR/code"
ln -s "$TMP_DIR" "$TMP_DIR-alias"
ln -s "$REPO/data/work" "$TMP_DIR/work-data-alias"
ln -s "$REPO" "$REPO/data/linked"
trap 'rm -rf "$TMP_DIR" "$TMP_DIR-alias"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/docker" <<STUB
#!/usr/bin/env bash
case "\$*" in
  "volume inspect repo-volume") echo '[{"Name":"repo-volume","Options":{"type":"none","o":"rbind","device":"$REPO"}}]' ;;
  "volume inspect plain-volume") echo '[{"Name":"plain-volume","Options":null}]' ;;
  "volume inspect repo-bind-volume") echo '[{"Name":"repo-bind-volume","Options":{"type":"none","o":"ro, bind","device":"$REPO"}}]' ;;
  "volume inspect project_scratch") echo '[{"Name":"project_scratch","Options":{"type":"none","o":"bind","device":"$REPO"}}]' ;;
  "volume inspect broken-volume") echo "Error response from daemon: permission denied" >&2; exit 1 ;;
  *) echo "Error response from daemon: get \${3}: no such volume" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP_DIR/bin/docker"
export DOCKER="$TMP_DIR/bin/docker"

fail() {
  echo "$*" >&2
  exit 1
}

compose_with_bind() {
  printf '{"services":{"dev-container":{"volumes":[{"type":"bind","source":"%s","target":"/x"}]}}}' "$1"
}

expect_rejected() {
  local description="$1"
  local mode="$2"
  local json="$3"

  if "$CHECK" "$mode" "$REPO" "$ALLOWED" <<< "$json" 2>"$TMP_DIR/stderr"; then
    fail "Expected rejection: $description"
  fi
  grep -Fq "Move this repository outside every container mount" "$TMP_DIR/stderr" || fail "Missing guidance for: $description"
}

expect_accepted() {
  local description="$1"
  local mode="$2"
  local json="$3"

  "$CHECK" "$mode" "$REPO" "$ALLOWED" <<< "$json" || fail "Expected acceptance: $description"
}

expect_rejected "repository" compose "$(compose_with_bind "$REPO")"
expect_rejected "repository ancestor" compose "$(compose_with_bind "$TMP_DIR")"
expect_rejected "filesystem root" compose "$(compose_with_bind /)"
expect_rejected "symlinked alias of an ancestor" compose "$(compose_with_bind "$TMP_DIR-alias")"
expect_rejected "repository subdirectory" compose "$(compose_with_bind "$REPO/scripts")"
expect_rejected "config directory" compose "$(compose_with_bind "$REPO/config")"
expect_rejected "another instance's data" compose "$(compose_with_bind "$REPO/data/other")"
expect_rejected "data subdirectory" compose "$(compose_with_bind "$ALLOWED/certs")"
expect_rejected "missing path under the repository" compose "$(compose_with_bind "$REPO/not-yet-created/dir")"
expect_rejected "named volume binding the repository" compose "{\"services\":{\"dev-container\":{\"volumes\":[{\"type\":\"volume\",\"source\":\"repo\",\"target\":\"/x\"}]}},\"volumes\":{\"repo\":{\"driver_opts\":{\"type\":\"none\",\"o\":\"bind\",\"device\":\"$REPO\"}}}}"
expect_rejected "secret file in the repository" compose "{\"services\":{\"dev-container\":{}},\"secrets\":{\"env\":{\"file\":\"$REPO/config/work/.env\"}}}"
expect_rejected "config file in the repository" compose "{\"services\":{\"dev-container\":{}},\"configs\":{\"env\":{\"file\":\"$REPO/config/work/.env\"}}}"
expect_rejected "external volume binding the repository" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"repo","target":"/x"}]}},"volumes":{"repo":{"name":"repo-volume","external":true}}}'
expect_rejected "existing volume binding the repository despite declared options" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"scratch","target":"/x"}]}},"volumes":{"scratch":{"name":"project_scratch","driver_opts":{"type":"tmpfs","device":"tmpfs"}}}}'
expect_rejected "volume whose inspection fails for another reason" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"broken","target":"/x"}]}},"volumes":{"broken":{"name":"broken-volume"}}}'
expect_accepted "new volume that does not exist yet" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"fresh","target":"/x"}]}},"volumes":{"fresh":{"name":"fresh-volume"}}}'
expect_rejected "external volume that cannot be inspected" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"gone","target":"/x"}]}},"volumes":{"gone":{"name":"gone-volume","external":true}}}'
expect_rejected "volumes_from" compose '{"services":{"dev-container":{"volumes_from":["other"]}}}'

grep -Fq "mount source $REPO/scripts exposes the repository" <("$CHECK" compose "$REPO" "$ALLOWED" <<< "$(compose_with_bind "$REPO/scripts")" 2>&1 || true) || fail "Errors must name the offending source"

expect_accepted "the instance data directory" compose "$(compose_with_bind "$ALLOWED")"
expect_accepted "the instance data directory through a symlink" compose "$(compose_with_bind "$TMP_DIR/work-data-alias")"
expect_accepted "unrelated code directory" compose "$(compose_with_bind "$TMP_DIR/code")"
expect_accepted "missing unrelated path" compose "$(compose_with_bind "$TMP_DIR/code/missing")"
expect_accepted "named volume without a device" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"cache","target":"/x"}]}},"volumes":{"cache":{}}}'
expect_accepted "named volume with a non-path device" compose '{"services":{"dev-container":{"volumes":[{"type":"volume","source":"scratch","target":"/x"}]}},"volumes":{"scratch":{"driver_opts":{"type":"tmpfs","device":"tmpfs"}}}}'
expect_accepted "secret file outside the repository" compose "{\"services\":{\"dev-container\":{}},\"secrets\":{\"key\":{\"file\":\"$TMP_DIR/code/key\"}}}"
expect_accepted "no volumes" compose '{"services":{"dev-container":{}}}'

expect_rejected "running container mounting the repository" inspect "[{\"Name\":\"/work\",\"Mounts\":[{\"Type\":\"bind\",\"Source\":\"$TMP_DIR\",\"Destination\":\"$TMP_DIR\"}]}]"
expect_rejected "running container with a volume binding the repository" inspect '[{"Name":"/work","Mounts":[{"Type":"volume","Name":"repo-volume","Source":"/var/lib/docker/volumes/repo-volume/_data","Destination":"/x"}]}]'
expect_rejected "running container with a plain bind volume (spaced options) of the repository" inspect '[{"Name":"/work","Mounts":[{"Type":"volume","Name":"repo-bind-volume","Destination":"/x"}]}]'
expect_rejected "running container with a volume that cannot be inspected" inspect '[{"Name":"/work","Mounts":[{"Type":"volume","Name":"gone-volume","Destination":"/x"}]}]'
expect_rejected "running container with an unnamed volume" inspect '[{"Name":"/work","Mounts":[{"Type":"volume","Destination":"/x"}]}]'
expect_accepted "running container with a plain volume" inspect '[{"Name":"/work","Mounts":[{"Type":"volume","Name":"plain-volume","Destination":"/x"}]}]'
expect_rejected "running container with volumes_from" inspect '[{"Name":"/work","HostConfig":{"VolumesFrom":["other"]},"Mounts":[]}]'
expect_accepted "running container mounting only allowed paths" inspect "[{\"Name\":\"/work\",\"Mounts\":[{\"Type\":\"bind\",\"Source\":\"$ALLOWED\",\"Destination\":\"/var/lib/dev-container/data\"},{\"Type\":\"bind\",\"Source\":\"$TMP_DIR/code\",\"Destination\":\"$TMP_DIR/code\"},{\"Type\":\"volume\",\"Name\":\"plain-volume\",\"Source\":\"/var/lib/docker/volumes/plain-volume/_data\",\"Destination\":\"/x\"}]}]"

if "$CHECK" compose "$REPO" "$REPO/data/linked" <<< "$(compose_with_bind "$TMP_DIR/code")" 2>"$TMP_DIR/stderr"; then
  fail "Expected a symlinked data directory to be rejected"
fi
grep -Fq "must be a real directory directly under" "$TMP_DIR/stderr" || fail "Missing symlinked data directory error"
