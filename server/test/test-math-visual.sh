#!/usr/bin/env bash
# Visual math rendering tests — verifies actual rendering quality via headless Chromium.
# Requires a running pandia server and Puppeteer (via mermaid-cli or standalone).
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

SERVE_PORT="${1:-13398}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test-math-rendering.mjs"

if ! command -v node >/dev/null 2>&1; then
  printf "  SKIP visual math tests: node not available\n"
  exit 0
fi

# --- Start a local server ---
PANDIA_SERVE="$PROJECT_DIR/cli/bin/pandia-serve"
"$PANDIA_SERVE" "$SERVE_PORT" &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; rm -rf "$MATH_DIR"; }
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf "http://localhost:${SERVE_PORT}/health" >/dev/null 2>&1 && break
  sleep 0.5
done

MATH_DIR=$(mktemp -d)

MATH_INPUT='# Math Rendering Test

The quadratic formula:

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

The Gaussian integral:

$$\int_{-\infty}^{\infty} e^{-x^2}\, dx = \sqrt{\pi}$$

The Collatz conjecture:

$$a_{n+1} = \begin{cases} \frac{a_n}{2} & \text{if } a_n \text{ is even} \\ 3a_n + 1 & \text{if } a_n \text{ is odd} \end{cases}$$
'

# --- Generate test HTML for both math engines ---
printf '%s' "$MATH_INPUT" | curl -s -X POST "http://localhost:${SERVE_PORT}/render?math=mathml" \
  --data-binary @- > "$MATH_DIR/mathml.html" 2>&1 || true
printf '%s' "$MATH_INPUT" | curl -s -X POST "http://localhost:${SERVE_PORT}/render?math=mathjax" \
  --data-binary @- > "$MATH_DIR/mathjax.html" 2>&1 || true

run_visual_check() {
  local label="$1" html_file="$2"
  shift 2
  local result rc
  result=$(node "$TEST_SCRIPT" "$html_file" "$@" 2>&1) && rc=0 || rc=$?

  # Forward individual PASS/FAIL lines
  while IFS= read -r line; do
    if echo "$line" | grep -q 'PASS'; then
      local msg
      msg=$(echo "$line" | sed 's/.*PASS //')
      PASS=$((PASS + 1))
      printf "  ${GREEN}PASS${RESET} %s: %s\n" "$label" "$msg"
    elif echo "$line" | grep -q 'FAIL'; then
      local msg
      msg=$(echo "$line" | sed 's/.*FAIL //')
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: ${label}: ${msg}"
      printf "  ${RED}FAIL${RESET} %s: %s\n" "$label" "$msg"
    elif echo "$line" | grep -q 'SKIP'; then
      printf "  SKIP %s: %s\n" "$label" "$(echo "$line" | sed 's/.*SKIP: //')"
    fi
  done <<< "$result"
}

# --- MathML visual tests ---
section "server: MathML visual rendering"

run_visual_check "MathML" "$MATH_DIR/mathml.html" \
  math-left-aligned math-rendered no-math-input-error \
  sqrt-has-vinculum integral-tall fraction-stacked

# --- MathJax visual tests ---
section "server: MathJax visual rendering"

run_visual_check "MathJax" "$MATH_DIR/mathjax.html" \
  math-left-aligned math-rendered no-math-input-error \
  sqrt-has-vinculum integral-tall fraction-stacked \
  math-fonts-loaded

# --- Diagrams must render with both math engines ---
section "server: diagrams render with mathjax math engine"

DIAGRAM_INPUT='# Diagram + MathJax Test

```graphviz
digraph { A -> B; }
```

$$x^2$$
'

printf '%s' "$DIAGRAM_INPUT" | curl -s -X POST "http://localhost:${SERVE_PORT}/render?math=mathjax" \
  --data-binary @- > "$MATH_DIR/mathjax-diagrams.html" 2>&1 || true

mathjax_diagram_html=$(cat "$MATH_DIR/mathjax-diagrams.html")
# Diagrams may be inline SVG or base64-encoded data URIs
if echo "$mathjax_diagram_html" | grep -q '<svg\|data:image/svg'; then
  PASS=$((PASS + 1))
  printf "  ${GREEN}PASS${RESET} MathJax mode renders diagrams as inline SVG\n"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: MathJax mode renders diagrams as inline SVG"
  printf "  ${RED}FAIL${RESET} MathJax mode renders diagrams as inline SVG\n"
fi

print_summary
exit $FAIL
