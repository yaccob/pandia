#!/usr/bin/env bash
# Container integration tests — runs against a pure image (no source mounts)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# --- Start container (pure image, no source mounts) ---
$RT stop "$CONTAINER" >/dev/null 2>&1 || true
$RT rm -f "$CONTAINER" >/dev/null 2>&1 || true
$RT run --rm -d --name "$CONTAINER" -p "${PORT}:${PORT}" -v "$PROJECT_DIR:/data" \
  "$IMAGE" pandia-serve "$PORT" >/dev/null 2>&1

for i in $(seq 1 30); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done

# --- POST /render: all diagram types as inline SVG ---

printf "\n${BOLD}container: /render diagram types (HTML)${RESET}\n"

test_render() {
  local type="$1" input="$2" extra_params="${3:-}"
  local body
  body=$(printf '```%s\n%s\n```' "$type" "$input")
  local result
  result=$(curl -s -X POST "http://localhost:${PORT}/render${extra_params}" --data-binary "$body" 2>&1) || true
  if echo "$result" | grep -q '<svg'; then ok "/render $type (SVG)"
  elif echo "$result" | grep -q 'markmap-container'; then ok "/render $type (markmap)"
  else fail "/render $type"; fi
}

test_render plantuml "Alice -> Bob: Hello"
test_render graphviz "digraph{A->B}"
test_render mermaid "graph LR; A-->B"
test_render nomnoml "[User] -> [App]"
test_render dbml "Table t { id integer [primary key] }"
test_render wavedrom '{ "signal": [{ "name": "clk", "wave": "p.." }] }'
test_render d2 "x -> y -> z"
test_render tikz '\begin{tikzpicture}\draw(0,0)--(1,1);\end{tikzpicture}'
test_render markmap '# Root
## A
## B'

# --- POST /render example.md completeness ---

printf "\n${BOLD}container: /render example.md completeness${RESET}\n"

# Render example.md via /render
curl -sf -X POST "http://localhost:${PORT}/render" \
  --data-binary @"$PROJECT_DIR/docs/example.md" > example-container.html 2>&1 || fail "/render example.md"
sleep 1

check_render_section() {
  local id="$1" label="$2"
  local count
  count=$(sed -n "/id=\"${id}/,/^<h[0-9]/p" example-container.html | grep -c '<svg\|<img' || true)
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
check_render_section "tikz--vector-drawing" "TikZ"
check_render_section "nomnoml--uml-diagrams" "Nomnoml"
check_render_section "dbml--database-schema" "DBML"
check_render_section "d2--declarative-diagrams" "D2"
check_render_section "wavedrom--digital-timing" "WaveDrom"
# Markmap (inline HTML, not img/svg)
if grep -q 'markmap-container' example-container.html; then
  ok "/render Markmap"
else
  fail "/render Markmap not rendered"
fi
# No unrendered diagram code blocks
unrendered=$(grep -o '<pre class="[^"]*"' example-container.html | grep -v 'sourceCode\|code-block' || true)
if [[ -z "$unrendered" ]]; then
  ok "/render no unrendered diagram blocks"
else
  fail "/render has unrendered blocks: $unrendered"
fi

rm -f example-container.html

# --- Parameters ---

printf "\n${BOLD}container: /render parameters${RESET}\n"

# format=pdf
pdf_result=$(curl -s -o /dev/null -w "%{content_type}" -X POST "http://localhost:${PORT}/render?format=pdf" \
  --data-binary '# PDF test' 2>&1) || true
if echo "$pdf_result" | grep -q 'application/pdf'; then
  ok "/render format=pdf returns PDF content type"
else
  fail "/render format=pdf returns PDF content type (got: $pdf_result)"
fi

# math=mathml
mathml_result=$(curl -s -X POST "http://localhost:${PORT}/render?math=mathml" \
  --data-binary 'Math: $$x^2$$' 2>&1) || true
if echo "$mathml_result" | grep -q '<math'; then
  ok "/render math=mathml produces MathML"
else
  fail "/render math=mathml produces MathML"
fi

# default math (mathml) with left-aligned CSS
curl -s -X POST "http://localhost:${PORT}/render" \
  --data-binary 'Math: $$x^2$$' > /tmp/pandia-test-math.html 2>&1 || true
if grep -q 'text-align.*left' /tmp/pandia-test-math.html 2>/dev/null; then
  ok "/render default math is left-aligned (CSS)"
else
  fail "/render default math is left-aligned"
fi

# center_math must not inject left-align CSS
curl -s -X POST "http://localhost:${PORT}/render?center_math=true" \
  --data-binary 'Math: $$x^2$$' > /tmp/pandia-test-math-center.html 2>&1 || true
if grep -q 'math.*text-align.*left' /tmp/pandia-test-math-center.html 2>/dev/null; then
  fail "/render center_math=true must not inject left-align CSS"
else
  ok "/render center_math=true does not inject left-align CSS"
fi
rm -f /tmp/pandia-test-math.html /tmp/pandia-test-math-center.html

# default math engine should be mathml
default_math_result=$(curl -s -X POST "http://localhost:${PORT}/render" \
  --data-binary 'Math: $$x^2$$' 2>&1) || true
if echo "$default_math_result" | grep -q '<math'; then
  ok "/render default math engine is MathML"
else
  fail "/render default math engine is MathML (got MathJax)"
fi

# mathml must have left-alignment CSS
mathml_align_result=$(curl -s -X POST "http://localhost:${PORT}/render?math=mathml" \
  --data-binary 'Math: $$x^2$$' 2>&1) || true
if echo "$mathml_align_result" | grep -q 'math.*text-align.*left\|display.*block.*text-align.*left'; then
  ok "/render MathML has CSS left-alignment"
else
  fail "/render MathML has CSS left-alignment"
fi

# mathjax must not contain %%URL%% font placeholders
mathjax_fonts_result=$(curl -s -X POST "http://localhost:${PORT}/render?math=mathjax" \
  --data-binary 'Math: $$x^2$$' 2>&1) || true
if echo "$mathjax_fonts_result" | grep -q '%%URL%%'; then
  fail "/render MathJax fonts must not contain %%URL%% placeholders"
else
  ok "/render MathJax fonts are loadable (no %%URL%% placeholders)"
fi

# maxwidth
mw_result=$(curl -s -X POST "http://localhost:${PORT}/render?maxwidth=40em" \
  --data-binary '# Width' 2>&1) || true
if echo "$mw_result" | grep -q '40em'; then
  ok "/render maxwidth=40em"
else
  fail "/render maxwidth=40em"
fi

# invalid format
invalid_result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${PORT}/render?format=docx" \
  --data-binary '# Test' 2>&1) || true
http_code=$(echo "$invalid_result" | tail -1)
if [[ "$http_code" == "400" ]]; then
  ok "/render rejects invalid format"
else
  fail "/render rejects invalid format (got $http_code)"
fi

# empty body
empty_result=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${PORT}/render" \
  -d '' 2>&1) || true
http_code=$(echo "$empty_result" | tail -1)
if [[ "$http_code" == "400" ]]; then
  ok "/render rejects empty body"
else
  fail "/render rejects empty body (got $http_code)"
fi

# wrong method
method_result=$(curl -s -w "\n%{http_code}" "http://localhost:${PORT}/render" 2>&1) || true
http_code=$(echo "$method_result" | tail -1)
if [[ "$http_code" == "405" ]]; then
  ok "/render GET returns 405"
else
  fail "/render GET returns 405 (got $http_code)"
fi


# --- Server rendering tests (reuse running container) ---
printf "\n${BOLD}Server rendering tests (diagram layout):${RESET}\n"
if node "$PROJECT_DIR/server/test/test-diagram-layout.mjs" "http://localhost:${PORT}" 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: diagram layout"
fi

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
