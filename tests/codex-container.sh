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

marker_source="$FIXTURE_ROOT/data/home/.codex/persisted-marker"
persistent_home="$FIXTURE_ROOT/data/home"
mkdir -p "${marker_source%/*}"
printf 'persisted\n' > "$marker_source"

docker run --rm \
  --entrypoint /bin/bash \
  --env PERSISTENT_HOME="$persistent_home" \
  --env PERSISTED_MARKER_SOURCE="$marker_source" \
  --volume "$FIXTURE_ROOT:$FIXTURE_ROOT" \
  --volume "$ROOT/tests/codex-installation.sh:/tmp/codex-installation.sh:ro" \
  "$IMAGE" \
  -ceu '/usr/local/bin/link-home "$PERSISTENT_HOME" "$HOME"; /tmp/codex-installation.sh'
