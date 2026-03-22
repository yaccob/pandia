#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../test/helpers.sh"

section "cli: --watch mode"

kill_watch() {
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null || true
}

test_cli_watch_initial_build() {
  local tmpdir pid
  tmpdir=$(mktemp -d)
  echo '# Initial' > "$tmpdir/input.md"

  "$PANDIA" --watch --local -t html -o "$tmpdir/out" "$tmpdir/input.md" > "$tmpdir/watch.log" 2>&1 &
  pid=$!

  local i=0
  while [[ $i -lt 20 && ! -f "$tmpdir/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  assert_file_exists "$tmpdir/out.html" "--watch performs initial build"
  assert_contains "$(cat "$tmpdir/watch.log")" "Watching" "Watch mode shows watching message"

  kill_watch "$pid"
  rm -rf "$tmpdir"
}
test_cli_watch_initial_build

test_cli_watch_rebuilds_on_change() {
  local tmpdir pid
  tmpdir=$(mktemp -d)
  echo '# Version 1' > "$tmpdir/input.md"

  "$PANDIA" --watch --local -t html -o "$tmpdir/out" "$tmpdir/input.md" > "$tmpdir/watch.log" 2>&1 &
  pid=$!

  local i=0
  while [[ $i -lt 20 && ! -f "$tmpdir/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  local ts_before
  ts_before=$(stat -f%m "$tmpdir/out.html" 2>/dev/null || stat -c%Y "$tmpdir/out.html" 2>/dev/null)

  sleep 2

  echo '# Version 2 — changed content' > "$tmpdir/input.md"

  local rebuilt=false
  i=0
  while [[ $i -lt 20 ]]; do
    sleep 0.5; i=$((i + 1))
    local ts_after
    ts_after=$(stat -f%m "$tmpdir/out.html" 2>/dev/null || stat -c%Y "$tmpdir/out.html" 2>/dev/null)
    if [[ "$ts_after" != "$ts_before" ]]; then
      rebuilt=true
      break
    fi
  done

  $rebuilt && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "--watch rebuilds after source change"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "--watch rebuilds after source change"; ERRORS="${ERRORS}\n  FAIL: --watch did not rebuild within 10s"; }

  assert_contains "$(cat "$tmpdir/watch.log")" "Change detected" "Watch log shows change detected"
  assert_contains "$(cat "$tmpdir/out.html")" "Version 2" "Rebuilt output contains new content"

  kill_watch "$pid"
  rm -rf "$tmpdir"
}
test_cli_watch_rebuilds_on_change

print_summary
exit $FAIL
