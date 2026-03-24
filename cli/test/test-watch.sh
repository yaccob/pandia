#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

if [[ -z "$CONTAINER_RT" ]]; then
  printf "\n${BOLD}cli: --watch mode${RESET}\n"
  printf "  ${RED}SKIP${RESET} --watch tests: no container runtime (docker/podman) found\n"
  exit 0
fi

WATCH_PORT=13302
WATCH_CONTAINER="pandia-test-watch"
WATCH_TMPDIR=""

start_server() {
  $CONTAINER_RT stop "$WATCH_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_RT rm -f "$WATCH_CONTAINER" >/dev/null 2>&1 || true

  WATCH_TMPDIR=$(mktemp -d)

  $CONTAINER_RT run --rm -d --name "$WATCH_CONTAINER" \
    -p "${WATCH_PORT}:${WATCH_PORT}" \
    yaccob/pandia pandia-serve "$WATCH_PORT" >/dev/null 2>&1

  local i=0
  while [[ $i -lt 60 ]]; do
    if curl -sf "http://localhost:${WATCH_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

stop_server() {
  $CONTAINER_RT stop "$WATCH_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_RT rm -f "$WATCH_CONTAINER" >/dev/null 2>&1 || true
  if [[ -n "$WATCH_TMPDIR" && -d "$WATCH_TMPDIR" ]]; then
    rm -rf "$WATCH_TMPDIR"
  fi
  WATCH_TMPDIR=""
}

kill_watch() {
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null || true
}

section "cli: --watch mode (server: $CONTAINER_RT)"

if ! start_server; then
  printf "  ${RED}SKIP${RESET} --watch tests: server failed to start\n"
  stop_server
  exit 0
fi

test_cli_watch_initial_build() {
  local pid
  echo '# Initial' > "$WATCH_TMPDIR/input.md"

  "$PANDIA" --watch --server "http://localhost:${WATCH_PORT}" \
    -t html -o "$WATCH_TMPDIR/out.html" "$WATCH_TMPDIR/input.md" \
    > "$WATCH_TMPDIR/watch.log" 2>&1 &
  pid=$!

  local i=0
  while [[ $i -lt 20 && ! -f "$WATCH_TMPDIR/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  assert_file_exists "$WATCH_TMPDIR/out.html" "--watch performs initial build via server"
  assert_contains "$(cat "$WATCH_TMPDIR/watch.log")" "Watching" "Watch mode shows watching message"

  kill_watch "$pid"
}
test_cli_watch_initial_build

test_cli_watch_rebuilds_on_change() {
  local pid
  echo '# Version 1' > "$WATCH_TMPDIR/input.md"
  rm -f "$WATCH_TMPDIR/out.html"

  "$PANDIA" --watch --server "http://localhost:${WATCH_PORT}" \
    -t html -o "$WATCH_TMPDIR/out.html" "$WATCH_TMPDIR/input.md" \
    > "$WATCH_TMPDIR/watch.log" 2>&1 &
  pid=$!

  local i=0
  while [[ $i -lt 20 && ! -f "$WATCH_TMPDIR/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  local ts_before
  ts_before=$(stat -f%m "$WATCH_TMPDIR/out.html" 2>/dev/null || stat -c%Y "$WATCH_TMPDIR/out.html" 2>/dev/null)

  sleep 2

  echo '# Version 2 — changed content' > "$WATCH_TMPDIR/input.md"

  local rebuilt=false
  i=0
  while [[ $i -lt 20 ]]; do
    sleep 0.5; i=$((i + 1))
    local ts_after
    ts_after=$(stat -f%m "$WATCH_TMPDIR/out.html" 2>/dev/null || stat -c%Y "$WATCH_TMPDIR/out.html" 2>/dev/null)
    if [[ "$ts_after" != "$ts_before" ]]; then
      rebuilt=true
      break
    fi
  done

  $rebuilt && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "--watch rebuilds after source change"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "--watch rebuilds after source change"; ERRORS="${ERRORS}\n  FAIL: --watch did not rebuild within 10s"; }

  assert_contains "$(cat "$WATCH_TMPDIR/watch.log")" "Change detected" "Watch log shows change detected"
  assert_contains "$(cat "$WATCH_TMPDIR/out.html")" "Version 2" "Rebuilt output contains new content"

  kill_watch "$pid"
}
test_cli_watch_rebuilds_on_change

stop_server

print_summary
exit $FAIL
