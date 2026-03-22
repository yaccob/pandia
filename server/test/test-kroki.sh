#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../test/helpers.sh"

KROKI_AVAILABLE=false
if curl -sf --max-time 5 "https://kroki.io/health" >/dev/null 2>&1; then
  KROKI_AVAILABLE=true
fi

if ! $KROKI_AVAILABLE; then
  printf "\n${BOLD}kroki: remote rendering${RESET}\n"
  printf "  ${RED}SKIP${RESET} kroki tests: kroki.io not reachable\n"
  exit 0
fi

section "kroki: remote rendering (kroki.io)"

test_kroki_nomnoml() {
  local input='```nomnoml
[Hello] -> [World]
```'
  local out
  out=$(run_filter_kroki "$input" "https://kroki.io") || true
  assert_contains "$out" "<img" "Kroki nomnoml generates image element"
  assert_contains "$out" "kroki-" "Image uses kroki prefix"
}
test_kroki_nomnoml

test_kroki_d2() {
  local input='```d2
x -> y
```'
  local out
  out=$(run_filter_kroki "$input" "https://kroki.io") || true
  assert_contains "$out" "<img" "Kroki d2 generates image element"
}
test_kroki_d2

test_kroki_invalid_syntax() {
  local input='```nomnoml
this is not valid nomnoml @@@!!!
```'
  local out
  out=$(run_filter_kroki "$input" "https://kroki.io") || true
  # Kroki returns HTTP 200 with error SVG even for invalid input,
  # so the filter sees a valid output file — no error to detect
  assert_contains "$out" "<img" "Kroki produces image even for invalid syntax (server-side error image)"
}
test_kroki_invalid_syntax

test_kroki_pdf_output() {
  local input='```nomnoml
[Hello] -> [World]
```'
  run_filter_kroki_pdf_keep "$input" "https://kroki.io"
  local found
  found=$(ls "$WORK_DIR"/img/kroki-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "Kroki produces PDF file for PDF output"
  teardown_workdir
}
test_kroki_pdf_output

print_summary
exit $FAIL
