#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINK_HOME="$ROOT/scripts/link-home"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

assert_link_target() {
  local path="$1"
  local expected="$2"

  [[ -L "$path" ]] || fail "Expected a symlink at $path"
  [[ "$(readlink -- "$path")" == "$expected" ]] || fail "Unexpected link target at $path"
}

expect_failure() {
  local description="$1"
  shift

  if "$@" >"$TMP_DIR/failure-output" 2>&1; then
    fail "Expected failure: $description"
  fi
}

new_fixture() {
  local name="$1"

  SOURCE="$TMP_DIR/$name/source"
  DESTINATION="$TMP_DIR/$name/destination"
  mkdir -p "$SOURCE" "$DESTINATION"
}

new_fixture recursive-files
mkdir -p "$SOURCE/.config/tool" "$SOURCE/empty directory"
printf 'state\n' > "$SOURCE/.config/tool/state file.json"
printf 'hidden\n' > "$SOURCE/.hidden"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/.config/tool/state file.json" "$SOURCE/.config/tool/state file.json"
assert_link_target "$DESTINATION/.hidden" "$SOURCE/.hidden"
[[ "$(cat "$DESTINATION/.config/tool/state file.json")" == "state" ]] || fail "Nested file content did not resolve"
[[ ! -e "$DESTINATION/empty directory" ]] || fail "Empty source directories must have no effect"

new_fixture source-symlinks
printf 'external\n' > "$TMP_DIR/external file"
ln -s "$TMP_DIR/external file" "$SOURCE/external link"
ln -s "$TMP_DIR/missing target" "$SOURCE/dangling link"
mkdir -p "$TMP_DIR/external-directory"
printf 'nested\n' > "$TMP_DIR/external-directory/file"
ln -s "$TMP_DIR/external-directory" "$SOURCE/linked directory"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/external link" "$SOURCE/external link"
assert_link_target "$DESTINATION/dangling link" "$SOURCE/dangling link"
assert_link_target "$DESTINATION/linked directory" "$SOURCE/linked directory"
[[ "$(cat "$DESTINATION/external link")" == "external" ]] || fail "External source link did not resolve"
[[ -L "$DESTINATION/dangling link" && ! -e "$DESTINATION/dangling link" ]] || fail "Dangling source link was not retained"
[[ "$(cat "$DESTINATION/linked directory/file")" == "nested" ]] || fail "Source directory symlink was followed instead of retained"

new_fixture existing-destinations
printf 'new\n' > "$SOURCE/file"
printf 'old\n' > "$DESTINATION/file"
ln -s "$TMP_DIR/nowhere" "$DESTINATION/dangling"
printf 'replacement\n' > "$SOURCE/dangling"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/file" "$SOURCE/file"
assert_link_target "$DESTINATION/dangling" "$SOURCE/dangling"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/file" "$SOURCE/file"

new_fixture leaf-directory-conflict
printf 'safe\n' > "$SOURCE/00-safe"
printf 'source\n' > "$SOURCE/zz-conflict"
mkdir "$DESTINATION/zz-conflict"
mkdir "$TMP_DIR/ordered-find-bin"
cat > "$TMP_DIR/ordered-find-bin/find" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$LINK_HOME_TEST_FIRST" "$LINK_HOME_TEST_SECOND"
STUB
chmod +x "$TMP_DIR/ordered-find-bin/find"
expect_failure "destination leaf directory conflict" env PATH="$TMP_DIR/ordered-find-bin:$PATH" LINK_HOME_TEST_FIRST="$SOURCE/00-safe" LINK_HOME_TEST_SECOND="$SOURCE/zz-conflict" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ -d "$DESTINATION/zz-conflict" ]] || fail "Destination directory conflict was modified"
[[ ! -e "$DESTINATION/00-safe" ]] || fail "Destination conflict produced a partial overlay"

new_fixture parent-type-conflict
mkdir -p "$SOURCE/parent"
printf 'source\n' > "$SOURCE/parent/file"
printf 'not a directory\n' > "$DESTINATION/parent"
expect_failure "destination parent type conflict" "$LINK_HOME" "$SOURCE" "$DESTINATION"

new_fixture parent-symlink
mkdir -p "$SOURCE/parent" "$TMP_DIR/outside"
printf 'source\n' > "$SOURCE/parent/file"
ln -s "$TMP_DIR/outside" "$DESTINATION/parent"
expect_failure "destination parent symlink" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ ! -e "$TMP_DIR/outside/file" ]] || fail "Linker traversed a destination parent symlink"

new_fixture parent-mountpoint
mkdir -p "$SOURCE/parent/mounted" "$DESTINATION/parent/mounted" "$TMP_DIR/stub-bin"
printf 'source\n' > "$SOURCE/parent/mounted/file"
cat > "$TMP_DIR/stub-bin/mountpoint" <<'STUB'
#!/usr/bin/env bash
if [[ "${@: -1}" == "$LINK_HOME_TEST_MOUNTPOINT" ]]; then
  exit 0
fi
exit 1
STUB
chmod +x "$TMP_DIR/stub-bin/mountpoint"
expect_failure "destination parent mountpoint" env PATH="$TMP_DIR/stub-bin:$PATH" LINK_HOME_TEST_MOUNTPOINT="$DESTINATION/parent/mounted" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ ! -e "$DESTINATION/parent/mounted/file" ]] || fail "Linker traversed a destination mountpoint"

for reserved_path in .ssh/authorized_keys .ssh/id_ed25519.pub .ssh/agent.sock; do
  fixture_name="reserved-${reserved_path##*/}"
  new_fixture "$fixture_name"
  mkdir -p "$SOURCE/.ssh"
  printf 'reserved\n' > "$SOURCE/$reserved_path"
  expect_failure "runtime-managed path $reserved_path" "$LINK_HOME" "$SOURCE" "$DESTINATION"
  [[ ! -e "$DESTINATION/$reserved_path" ]] || fail "Created runtime-managed path $reserved_path"

  new_fixture "$fixture_name-descendant"
  mkdir -p "$SOURCE/$reserved_path"
  printf 'reserved descendant\n' > "$SOURCE/$reserved_path/child"
  expect_failure "runtime-managed path descendant $reserved_path/child" "$LINK_HOME" "$SOURCE" "$DESTINATION"
  [[ ! -e "$DESTINATION/$reserved_path" ]] || fail "Created runtime-managed path ancestor $reserved_path"
done

new_fixture identical-roots
printf 'source\n' > "$SOURCE/file"
expect_failure "identical source and destination roots" "$LINK_HOME" "$SOURCE" "$SOURCE"
[[ -f "$SOURCE/file" && ! -L "$SOURCE/file" ]] || fail "Identical roots modified the source"

new_fixture destination-inside-source
mkdir "$SOURCE/destination"
printf 'source\n' > "$SOURCE/file"
expect_failure "destination inside source" "$LINK_HOME" "$SOURCE" "$SOURCE/destination"

new_fixture source-inside-destination
SOURCE="$DESTINATION/source"
mkdir "$SOURCE"
printf 'source\n' > "$SOURCE/file"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/file" "$SOURCE/file"

new_fixture documented-mounted-layout
SOURCE="$DESTINATION/code/dev-container/data/home"
mkdir -p "$SOURCE/.config/tool"
printf 'state\n' > "$SOURCE/.config/tool/state.json"
"$LINK_HOME" "$SOURCE" "$DESTINATION"
assert_link_target "$DESTINATION/.config/tool/state.json" "$SOURCE/.config/tool/state.json"

new_fixture source-inside-destination-self-mapping
SOURCE="$DESTINATION/source"
mkdir -p "$SOURCE/source"
printf 'safe\n' > "$SOURCE/safe"
printf 'unsafe\n' > "$SOURCE/source/file"
expect_failure "selected file maps back into source" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ ! -e "$DESTINATION/safe" ]] || fail "Unsafe selection produced a partial overlay"
[[ -f "$SOURCE/source/file" && ! -L "$SOURCE/source/file" ]] || fail "Unsafe selection modified its source"

new_fixture source-inside-destination-exact-self-mapping
SOURCE="$DESTINATION/source"
mkdir "$SOURCE"
printf 'unsafe\n' > "$SOURCE/source"
expect_failure "selected file maps exactly to source root" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ -f "$SOURCE/source" && ! -L "$SOURCE/source" ]] || fail "Exact self-mapping modified its source"

new_fixture source-inside-destination-ancestor-mapping
SOURCE="$DESTINATION/code/dev-container/data/home"
mkdir -p "$SOURCE"
printf 'safe\n' > "$SOURCE/00-safe"
printf 'unsafe\n' > "$SOURCE/code"
expect_failure "selected file maps to source ancestor" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ ! -e "$DESTINATION/00-safe" ]] || fail "Source-ancestor selection produced a partial overlay"
[[ -f "$SOURCE/code" && ! -L "$SOURCE/code" ]] || fail "Source-ancestor selection modified its source"

new_fixture filesystem-root-destination
expect_failure "filesystem root destination" "$LINK_HOME" "$SOURCE" /

new_fixture destination-root-symlink
mkdir "$TMP_DIR/real-destination"
ln -s "$TMP_DIR/real-destination" "$DESTINATION/root-link"
printf 'source\n' > "$SOURCE/file"
expect_failure "destination root symlink with repeated trailing slashes" "$LINK_HOME" "$SOURCE" "$DESTINATION/root-link//"
[[ ! -e "$TMP_DIR/real-destination/file" ]] || fail "Destination root symlink was traversed"

new_fixture enumeration-failure
printf 'source\n' > "$SOURCE/file"
mkdir "$TMP_DIR/find-stub-bin"
cat > "$TMP_DIR/find-stub-bin/find" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TMP_DIR/find-stub-bin/find"
expect_failure "source enumeration failure" env PATH="$TMP_DIR/find-stub-bin:$PATH" "$LINK_HOME" "$SOURCE" "$DESTINATION"
[[ ! -e "$DESTINATION/file" ]] || fail "Enumeration failure produced a partial overlay"
