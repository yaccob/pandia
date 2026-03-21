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
curl -sf -X POST "http://localhost:${PORT}/render" -d "file=example.md&to=html&kroki_server=https://kroki.io" | grep -q '"ok":true' \
  && ok "/render HTML (with kroki)" || fail "/render HTML (with kroki)"
curl -sf -X POST "http://localhost:${PORT}/render" -d "file=example.md&to=pdf&kroki_server=https://kroki.io" | grep -q '"ok":true' \
  && ok "/render PDF (with kroki)" || fail "/render PDF (with kroki)"

# Verify the rendered HTML has all diagram sections (including Kroki)
printf "\n${BOLD}container: /render example.md completeness${RESET}\n"
sleep 3
# Use heading IDs for reliable section matching (avoids line-wrap and duplicate issues)
check_render_section() {
  local id="$1" label="$2"
  local count
  count=$(sed -n "/id=\"${id}/,/^<h[0-9]/p" example.html | grep -c '<svg\|<img' || true)
  if [[ "$count" -gt 0 ]]; then
    ok "/render $label"
  else
    fail "/render $label not rendered"
  fi
}

check_render_section "plantuml--sequence-diagram" "Sequence Diagram"
check_render_section "plantuml--class-diagram" "Class Diagram"
check_render_section "plantuml--ebnf-syntax" "EBNF Syntax"
check_render_section "graphviz--directed-graph" "Directed Graph"
check_render_section "graphviz--state-machine" "State Machine"
check_render_section "mermaid--flowchart" "Mermaid Flowchart"
check_render_section "mermaid--gantt-chart" "Mermaid Gantt"
check_render_section "ditaa--ascii-art" "Ditaa"
check_render_section "tikz--vector-drawing" "TikZ"
check_render_section "nomnoml--uml-diagrams" "Nomnoml"
check_render_section "dbml--database-schema" "DBML"
check_render_section "d2--declarative-diagrams" "D2"
check_render_section "wavedrom--digital-timing" "WaveDrom"
# Markmap (inline HTML, not img/svg)
if grep -q 'markmap-container' example.html; then
  ok "/render Markmap"
else
  fail "/render Markmap not rendered"
fi
# Kroki sections
check_render_section "bpmn--business" "BPMN (kroki)"
check_render_section "entity-relationship" "ERD (kroki)"
check_render_section "pikchr--technical" "Pikchr (kroki)"
# No unrendered diagram code blocks
unrendered=$(grep -o '<pre class="[^"]*"' example.html | grep -v 'sourceCode\|code-block' || true)
if [[ -z "$unrendered" ]]; then
  ok "/render no unrendered diagram blocks"
else
  fail "/render has unrendered blocks: $unrendered"
fi

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

# --- API parity: /render and /preview must support the same parameters ---

printf "\n${BOLD}container: API parity — kroki_server${RESET}\n"

# Write a test file with a kroki-only diagram type
$RT exec "$CONTAINER" sh -c 'printf "# Kroki Test\n\n\`\`\`pikchr\nbox \"A\"; arrow; box \"B\"\n\`\`\`\n" > /data/test-kroki-parity.md'

# /render with kroki_server must render the diagram (not leave it as code block)
curl -sf -X POST "http://localhost:${PORT}/render" \
  -d "file=test-kroki-parity.md&to=html&kroki_server=https://kroki.io" | grep -q '"ok":true' \
  && ok "/render accepts kroki_server parameter" \
  || fail "/render accepts kroki_server parameter"

sleep 1
if grep -q '<svg\|<img' test-kroki-parity.html 2>/dev/null; then
  ok "/render kroki_server renders diagram (not code block)"
else
  fail "/render kroki_server renders diagram (not code block)"
fi

# /preview with kroki_server (already tested above, but verify parity)
preview_body=$(printf '```pikchr\nbox "A"; arrow; box "B"\n```')
preview_html=$(curl -s -X POST "http://localhost:${PORT}/preview?kroki_server=https://kroki.io" \
  --data-binary "$preview_body" 2>&1) || true
if echo "$preview_html" | grep -q '<svg'; then
  ok "/preview kroki_server renders diagram"
else
  fail "/preview kroki_server renders diagram"
fi

# Both must contain inline SVG (not <img> references to files)
render_has_svg=$(grep -c '<svg' test-kroki-parity.html 2>/dev/null || true)
preview_has_svg=$(echo "$preview_html" | grep -c '<svg' || true)
if [[ "$render_has_svg" -gt 0 && "$preview_has_svg" -gt 0 ]]; then
  ok "/render and /preview both produce inline SVG for kroki diagrams"
else
  fail "/render and /preview both produce inline SVG for kroki diagrams (render=$render_has_svg, preview=$preview_has_svg)"
fi

printf "\n${BOLD}container: API parity — center_math${RESET}\n"

# Write a test file with display math
$RT exec "$CONTAINER" sh -c 'printf "Display: \$\$x^2+1\$\$\n" > /data/test-math-parity.md'

# /render with center_math
curl -sf -X POST "http://localhost:${PORT}/render" \
  -d "file=test-math-parity.md&to=html&center_math=true" | grep -q '"ok":true' \
  && ok "/render accepts center_math parameter" \
  || fail "/render accepts center_math parameter"

sleep 1
render_math=$(cat test-math-parity.html 2>/dev/null) || true

# Default (no center_math) should be left-aligned
curl -sf -X POST "http://localhost:${PORT}/render" \
  -d "file=test-math-parity.md&to=html" | grep -q '"ok":true' || true
sleep 1
if grep -q "displayAlign.*left\|text-align.*left" test-math-parity.html 2>/dev/null; then
  ok "/render default math is left-aligned"
else
  fail "/render default math is left-aligned"
fi

# /preview default should also be left-aligned
preview_math=$(curl -s -X POST "http://localhost:${PORT}/preview" \
  --data-binary 'Display: $$x^2+1$$' 2>&1) || true
if echo "$preview_math" | grep -q 'text-align.*left\|displayAlign.*left\|display="block"'; then
  ok "/preview default math is left-aligned (or uses MathML block)"
else
  fail "/preview default math is left-aligned"
fi

# /preview with center_math should NOT left-align
preview_math_center=$(curl -s -X POST "http://localhost:${PORT}/preview?center_math=true" \
  --data-binary 'Display: $$x^2+1$$' 2>&1) || true
if echo "$preview_math_center" | grep -q "displayAlign.*left"; then
  fail "/preview center_math=true must not left-align"
else
  ok "/preview center_math=true does not left-align"
fi

printf "\n${BOLD}container: API parity — maxwidth${RESET}\n"

# /render with custom maxwidth
curl -sf -X POST "http://localhost:${PORT}/render" \
  -d "file=test-math-parity.md&to=html&maxwidth=40em" | grep -q '"ok":true' || true
sleep 1
if grep -q '40em' test-math-parity.html 2>/dev/null; then
  ok "/render respects maxwidth parameter"
else
  fail "/render respects maxwidth parameter"
fi

# /preview with custom maxwidth
preview_mw=$(curl -s -X POST "http://localhost:${PORT}/preview?maxwidth=40em" \
  --data-binary '# Test' 2>&1) || true
if echo "$preview_mw" | grep -q '40em'; then
  ok "/preview respects maxwidth parameter"
else
  fail "/preview respects maxwidth parameter"
fi

# Cleanup test files
$RT exec "$CONTAINER" sh -c 'rm -f /data/test-kroki-parity.* /data/test-math-parity.*' 2>/dev/null || true

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
