#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

if [[ -z "$CONTAINER_RT" ]]; then
  printf "\n${BOLD}cli: --serve mode${RESET}\n"
  printf "  ${RED}SKIP${RESET} --serve tests: no container runtime (docker/podman) found\n"
  exit 0
fi

SERVE_PORT=13300
SERVE_CONTAINER="pandia-test-serve"
SERVE_TMPDIR=""

start_serve() {
  $CONTAINER_RT stop "$SERVE_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_RT rm -f "$SERVE_CONTAINER" >/dev/null 2>&1 || true

  SERVE_TMPDIR=$(mktemp -d)
  echo '# Serve Test' > "$SERVE_TMPDIR/test-serve.md"

  # Mount current source files to test latest code
  $CONTAINER_RT run --rm -d --name "$SERVE_CONTAINER" \
    -p "${SERVE_PORT}:${SERVE_PORT}" \
    -v "$SERVE_TMPDIR:/data" \
    -v "$PROJECT_DIR/pandia-server.mjs:/usr/local/share/pandia/pandia-server.mjs:ro" \
    -v "$PROJECT_DIR/diagram-filter.lua:/usr/local/share/pandoc/filters/diagram-filter.lua:ro" \
    -v "$PROJECT_DIR/markmap-render.mjs:/usr/local/share/pandia/markmap-render.mjs:ro" \
    -v "$PROJECT_DIR/diagram-renderer.mjs:/usr/local/lib/node_modules/diagram-renderer.mjs:ro" \
    yaccob/pandia --serve "$SERVE_PORT" >/dev/null 2>&1

  local i=0
  while [[ $i -lt 60 ]]; do
    if curl -sf "http://localhost:${SERVE_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

stop_serve() {
  $CONTAINER_RT stop "$SERVE_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_RT rm -f "$SERVE_CONTAINER" >/dev/null 2>&1 || true
  if [[ -n "$SERVE_TMPDIR" && -d "$SERVE_TMPDIR" ]]; then
    rm -rf "$SERVE_TMPDIR"
  fi
  SERVE_TMPDIR=""
}

section "cli: --serve mode (container: $CONTAINER_RT)"

if ! start_serve; then
  printf "  ${RED}SKIP${RESET} --serve tests: container failed to start\n"
  stop_serve
  exit 0
fi

test_serve_health() {
  local out
  out=$(curl -sf "http://localhost:${SERVE_PORT}/health" 2>&1)
  assert_contains "$out" "ok" "/health returns ok"
}
test_serve_health

test_serve_render_html() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "file=test-serve.md&to=html" 2>&1) || true
  assert_contains "$out" '"ok":true' "/render returns ok:true"
  assert_contains "$out" "test-serve.html" "/render reports html output file"
  sleep 1
  assert_file_exists "$SERVE_TMPDIR/test-serve.html" "HTML file created by server"
}
test_serve_render_html

test_serve_render_pdf() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "file=test-serve.md&to=pdf" 2>&1) || true
  assert_contains "$out" '"ok":true' "/render PDF returns ok:true"
  sleep 1
  assert_file_exists "$SERVE_TMPDIR/test-serve.pdf" "PDF file created by server"
}
test_serve_render_pdf

test_serve_render_both() {
  rm -f "$SERVE_TMPDIR/test-serve.html" "$SERVE_TMPDIR/test-serve.pdf"
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "file=test-serve.md&to=html,pdf" 2>&1) || true
  assert_contains "$out" '"ok":true' "/render both formats returns ok:true"
  sleep 1
  [[ -f "$SERVE_TMPDIR/test-serve.html" && -f "$SERVE_TMPDIR/test-serve.pdf" ]] \
    && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Both HTML and PDF created"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Both HTML and PDF created"; ERRORS="${ERRORS}\n  FAIL: not both files created"; }
}
test_serve_render_both

test_serve_missing_file_param() {
  local out
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "to=html" 2>&1) || true
  local http_code body
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$body" "error" "Missing file param returns error"
  assert_contains "$http_code" "400" "Missing file param returns 400"
}
test_serve_missing_file_param

test_serve_nonexistent_file() {
  local out
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "file=nonexistent.md&to=html" 2>&1) || true
  local http_code body
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$body" "error" "Nonexistent file returns error"
  assert_contains "$http_code" "500" "Nonexistent file returns 500"
}
test_serve_nonexistent_file

test_serve_404() {
  local out
  out=$(curl -s -w "\n%{http_code}" "http://localhost:${SERVE_PORT}/bogus" 2>&1) || true
  local http_code
  http_code=$(echo "$out" | tail -1)
  assert_contains "$http_code" "404" "Unknown route returns 404"
}
test_serve_404

# --- /preview endpoint ------------------------------------------------

section "serve: /preview endpoint"

test_preview_basic_html() {
  local out
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '# Hello

Some text' 2>&1) || true
  local http_code body
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$http_code" "200" "/preview returns 200"
  assert_contains "$body" "Hello" "/preview output contains heading"
}
test_preview_basic_html

test_preview_returns_html_content_type() {
  local headers
  headers=$(curl -s -D - -o /dev/null -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '# Test' 2>&1) || true
  assert_contains "$headers" "text/html" "/preview returns text/html content type"
}
test_preview_returns_html_content_type

test_preview_graphviz_inline() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '# Graph

```graphviz
digraph { A -> B; }
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview graphviz is rendered as inline SVG"
  assert_not_contains "$out" "img/graphviz" "/preview graphviz does not reference filesystem path"
}
test_preview_graphviz_inline

test_preview_dir_block() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```dir
root
  child
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview dir block renders SVG inline"
}
test_preview_dir_block

test_preview_math_mathml() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary 'Euler: $e^{i\pi}+1=0$' 2>&1) || true
  assert_contains "$out" "<math" "/preview renders math as MathML (no MathJax needed)"
  assert_not_contains "$out" "mathjax" "/preview does not include MathJax script"
}
test_preview_math_mathml

test_preview_markmap() {
  local out http_code
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```markmap
# Root
## A
## B
```' 2>&1) || true
  http_code=$(echo "$out" | tail -1)
  out=$(echo "$out" | sed '$d')
  assert_contains "$http_code" "200" "/preview markmap returns 200 (not 500)"
  assert_not_contains "$out" "markmap error" "/preview markmap does not contain error message"
  assert_not_contains "$out" "markmap-render.mjs failed" "/preview markmap render does not fail"
  assert_contains "$out" "Root" "/preview markmap includes node content"
}
test_preview_markmap

test_preview_empty_body() {
  local out
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/preview" \
    -d '' 2>&1) || true
  local http_code body
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$http_code" "400" "/preview with empty body returns 400"
  assert_contains "$body" "error" "/preview with empty body returns error message"
}
test_preview_empty_body

test_preview_whitespace_only() {
  local out
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '   ' 2>&1) || true
  local http_code
  http_code=$(echo "$out" | tail -1)
  assert_contains "$http_code" "400" "/preview with whitespace-only body returns 400"
}
test_preview_whitespace_only

test_preview_multiple_diagrams() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```graphviz
digraph{A->B}
```

```graphviz
digraph{C->D}
```' 2>&1) || true
  local count
  count=$(echo "$out" | grep -o "<svg" | wc -l | tr -d ' ')
  [[ "$count" -ge 2 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "/preview inlines multiple diagrams as SVG"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "/preview inlines multiple diagrams as SVG"; ERRORS="${ERRORS}\n  FAIL: expected >=2 <svg>, got $count"; }
}
test_preview_multiple_diagrams

test_preview_maxwidth_param() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview?maxwidth=40em" \
    --data-binary '# Width test' 2>&1) || true
  assert_contains "$out" "40em" "/preview respects maxwidth query parameter"
}
test_preview_maxwidth_param

test_preview_default_maxwidth() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '# Width test' 2>&1) || true
  assert_contains "$out" "60em" "/preview uses 60em default maxwidth"
}
test_preview_default_maxwidth

# --- Request validation ---

section "serve: request validation"

test_render_invalid_format() {
  local out http_code
  out=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:${SERVE_PORT}/render" \
    -d "file=test.md&to=docx" 2>&1) || true
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$http_code" "400" "/render rejects invalid format 'docx'"
  assert_contains "$body" "error" "/render returns error for invalid format"
}
test_render_invalid_format

test_preview_wrong_method() {
  local out http_code
  out=$(curl -s -w "\n%{http_code}" "http://localhost:${SERVE_PORT}/preview" 2>&1) || true
  http_code=$(echo "$out" | tail -1)
  assert_contains "$http_code" "405" "/preview GET returns 405 Method Not Allowed"
}
test_preview_wrong_method

test_render_get_invalid_format() {
  local out http_code
  out=$(curl -s -w "\n%{http_code}" "http://localhost:${SERVE_PORT}/render?file=test.md&to=docx" 2>&1) || true
  http_code=$(echo "$out" | tail -1)
  body=$(echo "$out" | sed '$d')
  assert_contains "$http_code" "400" "/render GET rejects invalid format"
  assert_contains "$body" "error" "/render GET returns error for invalid format"
}
test_render_get_invalid_format

# --- SVG quality checks for preview ---

section "serve: SVG quality in /preview"

test_preview_svg_has_viewbox() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```graphviz
digraph { A -> B; }
```' 2>&1) || true
  assert_contains "$out" "viewBox" "/preview SVG has viewBox attribute (needed for scaling)"
}
test_preview_svg_has_viewbox

test_preview_plantuml_no_preserveaspectratio_none() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```plantuml
Alice -> Bob: Hello
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview plantuml renders as SVG"
  assert_not_contains "$out" 'preserveAspectRatio="none"' \
    "/preview plantuml SVG must not have preserveAspectRatio=none (breaks scaling)"
}
test_preview_plantuml_no_preserveaspectratio_none

test_preview_plantuml_has_viewbox() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```plantuml
Alice -> Bob: Hello
```' 2>&1) || true
  assert_contains "$out" "viewBox" "/preview plantuml SVG has viewBox"
}
test_preview_plantuml_has_viewbox

# --- Native diagram types (via diagram-renderer.mjs) ---

section "serve: native diagram types"

test_preview_nomnoml() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```nomnoml
[User] -> [App]
[App] -> [Database]
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview nomnoml renders as inline SVG"
  assert_not_contains "$out" "error" "/preview nomnoml has no error"
}
test_preview_nomnoml

test_preview_d2() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```d2
x -> y -> z
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview d2 renders as inline SVG"
  assert_not_contains "$out" "error" "/preview d2 has no error"
}
test_preview_d2

test_preview_svgbob() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```svgbob
    +---+
    | A |
    +---+
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview svgbob renders as inline SVG"
}
test_preview_svgbob

test_preview_dbml() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```dbml
Table users {
  id integer [primary key]
  username varchar
  email varchar
}

Table posts {
  id integer [primary key]
  title varchar
  user_id integer [ref: > users.id]
}
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview dbml renders as inline SVG"
  assert_not_contains "$out" "error" "/preview dbml has no error"
}
test_preview_dbml

test_preview_wavedrom() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview" \
    --data-binary '```wavedrom
{ "signal": [{ "name": "clk", "wave": "p....." }, { "name": "data", "wave": "x.345x" }] }
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview wavedrom renders as inline SVG"
  assert_not_contains "$out" "error" "/preview wavedrom has no error"
}
test_preview_wavedrom

# --- Kroki via /preview ---

section "serve: kroki_server query parameter"

test_preview_kroki_pikchr() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview?kroki_server=https://kroki.io" \
    --data-binary '```pikchr
box "A"
arrow
box "B"
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview pikchr renders via kroki_server param"
  assert_not_contains "$out" "error" "/preview pikchr has no error"
}
test_preview_kroki_pikchr

test_preview_kroki_erd() {
  local out
  out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/preview?kroki_server=https://kroki.io" \
    --data-binary '```erd
[Person]
*name
height
weight
```' 2>&1) || true
  assert_contains "$out" "<svg" "/preview erd renders via kroki_server param"
  assert_not_contains "$out" "error" "/preview erd has no error"
}
test_preview_kroki_erd

stop_serve

print_summary
exit $FAIL
