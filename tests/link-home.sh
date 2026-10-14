#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINK_HOME="$ROOT/scripts/link-home"
TMP_DIR="$(mktemp -d)"
trap 'chmod -R u+rw "$TMP_DIR" 2>/dev/null; rm -rf "$TMP_DIR"' EXIT

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
  LIST="$TMP_DIR/$name/persist"
  mkdir -p "$SOURCE" "$DESTINATION"
}

link() {
  "$LINK_HOME" "$SOURCE" "$LIST" "$DESTINATION"
}

new_fixture file-and-directory
mkdir -p "$SOURCE/.config/tool" "$SOURCE/.claude/projects/existing" "$SOURCE/name with spaces"
printf 'state\n' > "$SOURCE/.config/tool/state file.json"
printf 'unlisted\n' > "$SOURCE/unlisted"
printf 'spaced\n' > "$SOURCE/name with spaces/file"
printf '# comment\n\n   \n  # indented comment\n.config/tool/state file.json\r\n.claude/projects/\nname with spaces/file' > "$LIST"
link
assert_link_target "$DESTINATION/.config/tool/state file.json" "$SOURCE/.config/tool/state file.json"
assert_link_target "$DESTINATION/.claude/projects" "$SOURCE/.claude/projects"
assert_link_target "$DESTINATION/name with spaces/file" "$SOURCE/name with spaces/file"
[[ "$(cat "$DESTINATION/.config/tool/state file.json")" == "state" ]] || fail "Listed file content did not resolve"
[[ -d "$DESTINATION/.config/tool" && ! -L "$DESTINATION/.config/tool" ]] || fail "Destination parents must be real directories"
printf 'session\n' > "$DESTINATION/.claude/projects/new-session"
[[ -f "$SOURCE/.claude/projects/new-session" ]] || fail "A file written through a listed directory must land in the source"
[[ ! -e "$DESTINATION/unlisted" ]] || fail "Unlisted source files must be ignored"

new_fixture missing-list
printf 'state\n' > "$SOURCE/file"
link
[[ -z "$(ls -A "$DESTINATION")" ]] || fail "A missing list file must link nothing"

new_fixture unreadable-list
printf 'state\n' > "$SOURCE/file"
mkdir "$LIST"
expect_failure "list path is a directory" link

new_fixture dangling-list
printf 'state\n' > "$SOURCE/file"
ln -s "$TMP_DIR/missing-list" "$LIST"
expect_failure "dangling list symlink" link

if (( EUID != 0 )); then
  new_fixture unreadable-list-file
  printf 'state\n' > "$SOURCE/file"
  printf 'file\n' > "$LIST"
  chmod 000 "$LIST"
  expect_failure "unreadable list file" link
fi

new_fixture symlink-entries
printf 'external\n' > "$TMP_DIR/external file"
mkdir -p "$TMP_DIR/external-directory"
printf 'nested\n' > "$TMP_DIR/external-directory/file"
ln -s "$TMP_DIR/external file" "$SOURCE/file link"
ln -s "$TMP_DIR/external-directory" "$SOURCE/directory link"
ln -s "$TMP_DIR/missing target" "$SOURCE/dangling link"
printf 'file link\ndirectory link\ndangling link\n' > "$LIST"
link
assert_link_target "$DESTINATION/file link" "$SOURCE/file link"
assert_link_target "$DESTINATION/directory link" "$SOURCE/directory link"
assert_link_target "$DESTINATION/dangling link" "$SOURCE/dangling link"
[[ "$(cat "$DESTINATION/directory link/file")" == "nested" ]] || fail "Listed directory symlink did not resolve"

new_fixture symlinked-source-parent
mkdir -p "$TMP_DIR/elsewhere"
printf 'state\n' > "$TMP_DIR/elsewhere/file"
ln -s "$TMP_DIR/elsewhere" "$SOURCE/parent"
printf 'parent/file\n' > "$LIST"
expect_failure "entry reached through a symlinked source parent" link

new_fixture existing-destinations
printf 'new\n' > "$SOURCE/file"
printf 'replacement\n' > "$SOURCE/dangling"
printf 'old\n' > "$DESTINATION/file"
ln -s "$TMP_DIR/nowhere" "$DESTINATION/dangling"
printf 'file\ndangling\n' > "$LIST"
link
assert_link_target "$DESTINATION/file" "$SOURCE/file"
assert_link_target "$DESTINATION/dangling" "$SOURCE/dangling"
link
assert_link_target "$DESTINATION/file" "$SOURCE/file"

new_fixture destination-directory-conflict
printf 'safe\n' > "$SOURCE/00-safe"
mkdir -p "$SOURCE/conflict" "$DESTINATION/conflict"
printf '00-safe\nconflict\n' > "$LIST"
expect_failure "existing real destination directory" link
[[ ! -e "$DESTINATION/00-safe" ]] || fail "A later invalid entry must leave nothing linked"

for entry in "/" "/absolute" "../escape" "a/../b" "./file" "a/./b" "a//b" ".ssh//authorized_keys" " leading" "trailing " "a//"; do
  new_fixture "invalid-$(printf '%s' "$entry" | tr -c 'a-z' '_')"
  printf 'safe\n' > "$SOURCE/safe"
  printf 'safe\n%s\n' "$entry" > "$LIST"
  expect_failure "invalid entry '$entry'" link
  [[ ! -e "$DESTINATION/safe" ]] || fail "Invalid entry '$entry' left a partial overlay"
done

new_fixture duplicate-entry
printf 'state\n' > "$SOURCE/file"
printf 'file\nfile/\n' > "$LIST"
expect_failure "duplicate entry" link

new_fixture nested-entries
mkdir -p "$SOURCE/dir"
printf 'state\n' > "$SOURCE/dir/file"
printf 'dir/file\ndir\n' > "$LIST"
expect_failure "nested entries" link

new_fixture missing-entry
printf 'state\n' > "$SOURCE/file"
printf 'file\n\nmissing\n' > "$LIST"
expect_failure "missing source entry" link
grep -Fq "$LIST:3:" "$TMP_DIR/failure-output" || fail "Errors must name the list file and line"
[[ ! -e "$DESTINATION/file" ]] || fail "A missing entry left a partial overlay"

for reserved_path in .ssh/authorized_keys .ssh/id_ed25519.pub .ssh/agent.sock .ssh; do
  fixture_name="reserved-$(printf '%s' "$reserved_path" | tr -c 'a-z' '_')"
  new_fixture "$fixture_name"
  mkdir -p "$SOURCE/.ssh"
  printf 'reserved\n' > "$SOURCE/.ssh/authorized_keys"
  [[ -e "$SOURCE/$reserved_path" ]] || printf 'reserved\n' > "$SOURCE/$reserved_path"
  printf '%s\n' "$reserved_path" > "$LIST"
  expect_failure "runtime-managed path $reserved_path" link
  [[ ! -e "$DESTINATION/.ssh" ]] || fail "Created runtime-managed path $reserved_path"
done

new_fixture reserved-descendant
mkdir -p "$SOURCE/.ssh/agent.sock"
printf 'child\n' > "$SOURCE/.ssh/agent.sock/child"
printf '.ssh/agent.sock/child\n' > "$LIST"
expect_failure "runtime-managed path descendant" link

new_fixture parent-type-conflict
mkdir -p "$SOURCE/parent"
printf 'source\n' > "$SOURCE/parent/file"
printf 'not a directory\n' > "$DESTINATION/parent"
printf 'parent/file\n' > "$LIST"
expect_failure "destination parent type conflict" link
grep -Fq "$LIST:1: destination parent is not a directory" "$TMP_DIR/failure-output" || fail "Destination parent errors must name the list line"

new_fixture parent-symlink
mkdir -p "$SOURCE/parent" "$TMP_DIR/outside"
printf 'source\n' > "$SOURCE/parent/file"
ln -s "$TMP_DIR/outside" "$DESTINATION/parent"
printf 'parent/file\n' > "$LIST"
expect_failure "destination parent symlink" link
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
printf 'parent/mounted/file\n' > "$LIST"
expect_failure "destination parent mountpoint" env PATH="$TMP_DIR/stub-bin:$PATH" LINK_HOME_TEST_MOUNTPOINT="$DESTINATION/parent/mounted" "$LINK_HOME" "$SOURCE" "$LIST" "$DESTINATION"
[[ ! -e "$DESTINATION/parent/mounted/file" ]] || fail "Linker traversed a destination mountpoint"

new_fixture identical-roots
printf 'source\n' > "$SOURCE/file"
printf 'file\n' > "$LIST"
expect_failure "identical source and destination roots" "$LINK_HOME" "$SOURCE" "$LIST" "$SOURCE"
[[ -f "$SOURCE/file" && ! -L "$SOURCE/file" ]] || fail "Identical roots modified the source"

new_fixture destination-inside-source
mkdir "$SOURCE/destination"
printf 'source\n' > "$SOURCE/file"
printf 'file\n' > "$LIST"
expect_failure "destination inside source" "$LINK_HOME" "$SOURCE" "$LIST" "$SOURCE/destination"

new_fixture source-inside-destination
SOURCE="$DESTINATION/code/dev-container/data/home"
mkdir -p "$SOURCE/.config/tool"
printf 'state\n' > "$SOURCE/.config/tool/state.json"
printf '.config/tool/state.json\n' > "$LIST"
link
assert_link_target "$DESTINATION/.config/tool/state.json" "$SOURCE/.config/tool/state.json"

new_fixture source-inside-destination-self-mapping
SOURCE="$DESTINATION/source"
mkdir -p "$SOURCE/source"
printf 'unsafe\n' > "$SOURCE/source/file"
printf 'source/file\n' > "$LIST"
expect_failure "entry maps back into source" link
[[ -f "$SOURCE/source/file" && ! -L "$SOURCE/source/file" ]] || fail "Self-mapping modified its source"

new_fixture source-inside-destination-exact-self-mapping
SOURCE="$DESTINATION/source"
mkdir "$SOURCE"
printf 'unsafe\n' > "$SOURCE/source"
printf 'source\n' > "$LIST"
expect_failure "entry maps exactly to source root" link
[[ -f "$SOURCE/source" && ! -L "$SOURCE/source" ]] || fail "Exact self-mapping modified its source"

new_fixture source-inside-destination-ancestor-mapping
SOURCE="$DESTINATION/code/dev-container/data/home"
mkdir -p "$SOURCE"
printf 'unsafe\n' > "$SOURCE/code"
printf 'code\n' > "$LIST"
expect_failure "entry maps to a source ancestor" link
[[ -f "$SOURCE/code" && ! -L "$SOURCE/code" ]] || fail "Source-ancestor mapping modified its source"

new_fixture filesystem-root-destination
expect_failure "filesystem root destination" "$LINK_HOME" "$SOURCE" "$LIST" /

new_fixture destination-root-symlink
mkdir "$TMP_DIR/real-destination"
ln -s "$TMP_DIR/real-destination" "$DESTINATION/root-link"
printf 'source\n' > "$SOURCE/file"
printf 'file\n' > "$LIST"
expect_failure "destination root symlink with repeated trailing slashes" "$LINK_HOME" "$SOURCE" "$LIST" "$DESTINATION/root-link//"
[[ ! -e "$TMP_DIR/real-destination/file" ]] || fail "Destination root symlink was traversed"
