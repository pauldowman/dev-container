#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 IMAGE" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="$1"
FIXTURE_ROOT="$(mktemp -d "$ROOT/.codex-container.XXXXXX")"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT

data_mount=/var/lib/dev-container/data
mkdir -p "$FIXTURE_ROOT/data/home/.codex"
printf 'persisted\n' > "$FIXTURE_ROOT/data/home/.codex/persisted-marker"
printf '.codex/persisted-marker\n' > "$FIXTURE_ROOT/data/persist"

docker run --rm \
  --entrypoint /bin/bash \
  --env DATA_MOUNT="$data_mount" \
  --env PERSISTED_MARKER_SOURCE="$data_mount/home/.codex/persisted-marker" \
  --volume "$FIXTURE_ROOT/data:$data_mount" \
  --volume "$ROOT/tests/codex-installation.sh:/tmp/codex-installation.sh:ro" \
  "$IMAGE" \
  -ceu '/usr/local/bin/link-home "$DATA_MOUNT/home" "$DATA_MOUNT/persist" "$HOME"; /tmp/codex-installation.sh'
