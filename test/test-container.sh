#!/usr/bin/env bash
# Container integration tests — runs against a pure image (no source mounts)
set -euo pipefail

PORT="${1:-13301}"
CONTAINER="pandia-test-all"
RT="${CONTAINER_RT:-$(command -v podman 2>/dev/null || command -v docker 2>/dev/null)}"
IMAGE="${IMAGE:-yaccob/pandia:latest}"
PASS=0
FAIL=0
ERRORS=""

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "$1"; ERRORS="${ERRORS}\n  FAIL: $1"; }

# --- Start container (pure image, no mounts except /data for render) ---
$RT stop "$CONTAINER" >/dev/null 2>&1 || true
$RT rm -f "$CONTAINER" >/dev/null 2>&1 || true
$RT run --rm -d --name "$CONTAINER" -p "${PORT}:${PORT}" -v "$PWD:/data" \
  "$IMAGE" --serve "$PORT" >/dev/null 2>&1

for i in $(seq 1 30); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done

printf "\n${BOLD}container: /render${RESET}\n"
curl -sf -X POST "http://localhost:${PORT}/render" -d "file=example.md&to=html" | grep -q '"ok":true' \
  && ok "/render HTML" || fail "/render HTML"
curl -sf -X POST "http://localhost:${PORT}/render" -d "file=example.md&to=pdf" | grep -q '"ok":true' \
  && ok "/render PDF" || fail "/render PDF"

printf "\n${BOLD}container: /preview diagram types${RESET}\n"
test_preview() {
  local type="$1" input="$2"
  local body
  body=$(printf '```%s\n%s\n```' "$type" "$input")
  local result
  result=$(curl -s -X POST "http://localhost:${PORT}/preview" --data-binary "$body" 2>&1) || true
  if echo "$result" | grep -q '<svg'; then ok "/preview $type (SVG)"
  elif echo "$result" | grep -q 'markmap-container'; then ok "/preview $type (markmap)"
  else fail "/preview $type"; fi
}

test_preview plantuml "Alice -> Bob: Hello"
test_preview graphviz "digraph{A->B}"
test_preview mermaid "graph LR; A-->B"
test_preview nomnoml "[User] -> [App]"
test_preview dbml "Table t { id integer [primary key] }"
test_preview wavedrom '{ "signal": [{ "name": "clk", "wave": "p.." }] }'
test_preview d2 "x -> y -> z"
test_preview tikz '\begin{tikzpicture}\draw(0,0)--(1,1);\end{tikzpicture}'
test_preview markmap '# Root
## A
## B'

printf "\n${BOLD}container: /preview kroki${RESET}\n"
body=$(printf '```pikchr\nbox "A"; arrow; box "B"\n```')
result=$(curl -s -X POST "http://localhost:${PORT}/preview?kroki_server=https://kroki.io" --data-binary "$body" 2>&1) || true
if echo "$result" | grep -q '<svg'; then ok "/preview pikchr (kroki)"
else fail "/preview pikchr (kroki)"; fi

# --- Cleanup ---
$RT stop "$CONTAINER" >/dev/null 2>&1 || true

printf "\n${BOLD}Results:${RESET} "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All $PASS tests passed${RESET}\n"
else
  printf "${RED}$FAIL failed${RESET}, $PASS passed\n"
  printf "${ERRORS}\n"
fi
exit $FAIL
