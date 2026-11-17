#!/bin/bash
# Lazurio: native macOS E2E of the agent-desktop candidate on a dedicated test Mac
# (Lazurio/agent-desktop#2). Start it in the graphical session, for example with
# `open -a Terminal lazurio-mac-e2e.command`, never over SSH: macOS grants
# Accessibility, Screen Recording and Automation to Terminal only there.
#
# It checks out the exact candidate, builds it, gives the desktop one frontmost
# Finder window (the suite's first gate needs exactly one), runs
# `AGENT_DESKTOP_E2E_EXCLUSIVE=1 bash tests/e2e/run.sh`, then the real-app
# inventory check of point 2 of the pull request, and writes everything to
# ~/lazurio-e2e/results-<UTC time>/. Nobody may use the Mac while it runs.
set -u

CANDIDATE="${CANDIDATE:-8e403858e43dd484437cb3ce815e979872abbc55}"
ELECTRON_APP="${ELECTRON_APP:-Visual Studio Code}"
base="$HOME/lazurio-e2e"
repo="$base/agent-desktop"
out="$base/results-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
exec > >(tee -a "$out/run.log") 2>&1

echo "== Lazurio Mac E2E, candidate $CANDIDATE, $(date -u)"
# Keep the display awake for the whole run.
caffeinate -d -w $$ &

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
for tool in git cargo rustup swiftc python3 osascript; do
  command -v "$tool" >/dev/null || { echo "missing: $tool"; echo "exit=2" > "$out/suite-exit.txt"; exit 2; }
done

if [ ! -d "$repo/.git" ]; then
  git clone https://github.com/Lazurio/agent-desktop.git "$repo" || exit 2
fi
cd "$repo" || exit 2
git fetch --quiet origin "$CANDIDATE" || git fetch --quiet origin
git checkout --quiet --detach "$CANDIDATE" || exit 2
{
  date -u; sw_vers; uname -m; git rev-parse HEAD; rustup show active-toolchain; swiftc --version 2>&1 | head -1
} | tee "$out/machine.txt"
[ "$(git rev-parse HEAD)" = "$CANDIDATE" ] || { echo "HEAD is not the candidate"; exit 2; }

echo "== Build"
cargo build --locked --release -p agent-desktop &&
  cargo build --locked --release -p agent-desktop-macos --bin agent-desktop-macos-helper &&
  cargo build --locked --profile release-ffi -p agent-desktop-ffi || { echo "exit=2" > "$out/suite-exit.txt"; exit 2; }
B="$repo/target/release/agent-desktop"

echo "== Permissions"
"$B" permissions | tee "$out/permissions.json"
echo

echo "== One frontmost window"
osascript -e 'tell application "Finder" to make new Finder window' \
          -e 'tell application "Finder" to activate'
sleep 2
"$B" list-windows | python3 -c '
import json, sys
windows = json.load(sys.stdin)["data"]
focused = [w for w in windows if w.get("is_focused") is True]
print("focused windows:", [w.get("app_name") for w in focused])
sys.exit(0 if len(focused) == 1 else 1)
' | tee "$out/frontmost.txt"

echo "== Native suite"
date -u | tee "$out/suite-start.txt"
AGENT_DESKTOP_E2E_EXCLUSIVE=1 bash tests/e2e/run.sh 2>&1 | tee "$out/suite.log"
status=${PIPESTATUS[0]}
date -u | tee "$out/suite-end.txt"
echo "exit=$status" | tee "$out/suite-exit.txt"

echo "== Real-app inventory check"
inv="$out/inventory.log"
step() { echo "\$ agent-desktop $*" >> "$inv"; "$B" "$@" >> "$inv" 2>&1; echo "[exit $?]" >> "$inv"; }
apps=(TextEdit Calculator Finder)
if [ -d "/Applications/$ELECTRON_APP.app" ]; then
  apps+=("$ELECTRON_APP")
  echo "electron app: $ELECTRON_APP" >> "$inv"
else
  echo "electron app: none installed ($ELECTRON_APP not found)" >> "$inv"
fi
started=()
for app in "${apps[@]}"; do
  if [ "$app" != Finder ] && ! pgrep -x "$app" >/dev/null; then
    step launch "$app" --timeout-ms 60000
    started+=("$app")
  fi
  sleep 3
  step list-apps --app "$app"
  step list-windows --app "$app"
  step snapshot --app "$app" -i --max-depth 3
done
step list-apps --app com.apple.TextEdit
step list-apps --app com.apple.calculator
step list-apps
# Close only what this script started.
for app in ${started[@]+"${started[@]}"}; do step close-app "$app"; done

grep -E 'PASS|FAIL|SKIP' "$out/suite.log" | sed 's/\x1b\[[0-9;]*m//g' > "$out/summary.txt"
echo "PASS=$(grep -c PASS "$out/summary.txt") FAIL=$(grep -c FAIL "$out/summary.txt") SKIP=$(grep -c SKIP "$out/summary.txt") exit=$status" | tee -a "$out/summary.txt"
echo "== Done $(date -u). Results: $out"
exit "$status"
