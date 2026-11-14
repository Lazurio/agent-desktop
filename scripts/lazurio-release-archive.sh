#!/usr/bin/env bash
# Packs and checks the per-target release archives of the Lazurio
# distribution (docs/operations/lazurio-fork-release.md).
#
#   scripts/lazurio-release-archive.sh pack <target> <version> <bin-dir> <out-dir>
#   scripts/lazurio-release-archive.sh check <archive> <target> <version>
#
# An archive holds the executables side by side under the exact names the
# engine needs at run time, which are also cargo's output names:
# agent-desktop and agent-desktop-macos-helper for macOS, because the engine
# finds its clipboard helper only next to itself and only under that basename,
# and agent-desktop.exe for Windows.
#
# `check` lists the archive, extracts it into a fresh private directory and
# checks the version. For macOS it then proves helper discovery: the extracted
# engine reads the clipboard with an empty PATH and must reach the packaged
# helper. A negative control places the helper under its target-suffixed
# sidecar name instead and must fail discovery, so the check cannot pass
# without finding the helper.
set -euo pipefail

HELPER=agent-desktop-macos-helper
WORK=

die() {
  echo "lazurio-release-archive: $*" >&2
  exit 1
}

entries_for() {
  case "$1" in
    aarch64-apple-darwin | x86_64-apple-darwin) echo "agent-desktop $HELPER" ;;
    x86_64-pc-windows-msvc) echo "agent-desktop.exe" ;;
    *) die "unsupported target '$1'" ;;
  esac
}

archive_name() {
  echo "agent-desktop-v$2-$1.tar.gz"
}

sorted_words() {
  printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' '
}

pack() {
  [ "$#" -eq 4 ] || die "usage: pack <target> <version> <bin-dir> <out-dir>"
  local target=$1 version=$2 bin=$3 out=$4 entry stage archive
  local entries
  read -r -a entries <<< "$(entries_for "$target")"
  mkdir -p "$out"
  stage=$(mktemp -d "${TMPDIR:-/tmp}/agent-desktop-pack.XXXXXX")
  for entry in "${entries[@]}"; do
    [ -f "$bin/$entry" ] || die "missing $bin/$entry"
    cp "$bin/$entry" "$stage/$entry"
    chmod 0755 "$stage/$entry"
  done
  archive="$out/$(archive_name "$target" "$version")"
  COPYFILE_DISABLE=1 tar -czf "$archive" -C "$stage" "${entries[@]}"
  rm -rf -- "$stage"
  echo "$archive"
}

clipboard_read() {
  local dir=$1 run=$2 out=$3
  mkdir -p "$run/home" "$run/tmp" "$run/nopath"
  env -i HOME="$run/home" TMPDIR="$run/tmp/" PATH="$run/nopath" \
    "$dir/agent-desktop" clipboard-get > "$out" 2> "$out.err" || true
}

judge() {
  python3 -I - "$@" <<'PY'
import json
import sys

mode, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        result = json.load(handle)
except (OSError, ValueError) as error:
    sys.exit(f"{mode}: clipboard-get printed no JSON envelope ({error})")
error = result.get("error") or {}
details = error.get("details") or {}
discovery_failed = details.get("kind") in ("clipboard_helper_invalid", "clipboard_helper_not_found")
if mode == "packaged":
    if result.get("ok") is True:
        print("packaged: the engine found the helper and read the clipboard through it")
        sys.exit(0)
    runtime = {"System clipboard is unavailable", "System clipboard read access is denied"}
    if error.get("message") in runtime and not discovery_failed:
        print(f"packaged: the engine reached the helper; clipboard access is unavailable here ({error['message']})")
        sys.exit(0)
    sys.exit(f"packaged: the engine did not reach the packaged helper: {json.dumps(error)}")
if result.get("ok") is False and discovery_failed and details.get("helper") == "agent-desktop-macos-helper":
    print(f"negative control: a helper under another name is not discovered ({details['kind']})")
    sys.exit(0)
sys.exit(f"negative control: discovery did not fail: {json.dumps(result)}")
PY
}

check() {
  [ "$#" -eq 3 ] || die "usage: check <archive> <target> <version>"
  local archive=$1 target=$2 version=$3 engine reported listing expected
  local entries
  read -r -a entries <<< "$(entries_for "$target")"
  [ -f "$archive" ] || die "missing $archive"
  [ "$(basename "$archive")" = "$(archive_name "$target" "$version")" ] ||
    die "$(basename "$archive") is not named $(archive_name "$target" "$version")"
  listing=$(tar -tzf "$archive" | LC_ALL=C sort | tr '\n' ' ')
  expected=$(sorted_words "${entries[@]}")
  [ "$listing" = "$expected" ] || die "archive lists '$listing', expected '$expected'"
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-desktop-archive.XXXXXX")
  trap 'rm -rf -- "$WORK"' EXIT
  mkdir "$WORK/package"
  tar -xzf "$archive" -C "$WORK/package"
  engine="$WORK/package/${entries[0]}"
  reported=$("$engine" --version | tr -d '\r')
  [ "$reported" = "agent-desktop $version" ] || die "engine reports '$reported', expected 'agent-desktop $version'"
  echo "version: $reported"
  case "$target" in
    *-apple-darwin)
      [ -x "$WORK/package/$HELPER" ] || die "$HELPER is not executable after extraction"
      clipboard_read "$WORK/package" "$WORK/run-packaged" "$WORK/packaged.json"
      judge packaged "$WORK/packaged.json" || { cat "$WORK/packaged.json.err" >&2; exit 1; }
      mkdir "$WORK/suffixed"
      cp "$WORK/package/agent-desktop" "$WORK/suffixed/agent-desktop"
      cp "$WORK/package/$HELPER" "$WORK/suffixed/$HELPER-$target"
      clipboard_read "$WORK/suffixed" "$WORK/run-suffixed" "$WORK/suffixed.json"
      judge suffixed "$WORK/suffixed.json" || { cat "$WORK/suffixed.json.err" >&2; exit 1; }
      ;;
  esac
  echo "OK: $(basename "$archive") holds a working engine layout for $target"
}

[ "$#" -ge 1 ] || die "usage: pack <target> <version> <bin-dir> <out-dir> | check <archive> <target> <version>"
command=$1
shift
case "$command" in
  pack) pack "$@" ;;
  check) check "$@" ;;
  *) die "unknown command '$command'" ;;
esac
