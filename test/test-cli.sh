#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

section "cli: version and help"

test_cli_version_long() {
  local out
  out=$("$PANDIA" --version 2>&1)
  assert_contains "$out" "pandia v" "--version shows version string"
  assert_contains "$out" "1.7.0" "--version shows correct version number"
}
test_cli_version_long

test_cli_version_short() {
  local out
  out=$("$PANDIA" -v 2>&1)
  assert_contains "$out" "pandia v" "-v shows version string"
}
test_cli_version_short

test_cli_help_long() {
  local out
  out=$("$PANDIA" --help 2>&1)
  assert_contains "$out" "Usage:" "--help shows usage"
  assert_contains "$out" "Options:" "--help shows options"
  assert_contains "$out" "-t, --to" "--help documents -t flag"
  assert_contains "$out" "--watch" "--help documents --watch"
  assert_contains "$out" "--server" "--help documents --server"
  assert_contains "$out" "--kroki" "--help documents --kroki"
}
test_cli_help_long

test_cli_help_short() {
  local out
  out=$("$PANDIA" -h 2>&1)
  assert_contains "$out" "Usage:" "-h shows usage"
}
test_cli_help_short

section "cli: argument validation errors"

test_cli_no_input() {
  local out rc
  out=$("$PANDIA" -t html 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "No input file" "No input file error message"
  assert_contains "$out" "pandia --help" "Suggests --help"
  assert_exit_nonzero "$rc" "Non-zero exit code"
}
test_cli_no_input

test_cli_file_not_found() {
  local out rc
  out=$("$PANDIA" -t html /nonexistent/file.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "not found" "File not found error message"
  assert_exit_nonzero "$rc" "Non-zero exit code"
}
test_cli_file_not_found

test_cli_unknown_format() {
  local out rc
  out=$("$PANDIA" -t docx test.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "Unknown format" "Unknown format error message"
  assert_contains "$out" "docx" "Error includes the bad format name"
  assert_exit_nonzero "$rc" "Non-zero exit code"
}
test_cli_unknown_format

test_cli_unknown_option() {
  local out rc
  out=$("$PANDIA" --bogus test.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "Unknown option" "Unknown option shows error"
  assert_exit_nonzero "$rc" "Non-zero exit code"
}
test_cli_unknown_option

section "cli: local rendering"

test_cli_html_output() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t html -o "$tmpdir/out" "$tmpdir/input.md" 2>&1)
  assert_contains "$out" "Generating" "Shows generating message"
  assert_file_exists "$tmpdir/out.html" "HTML file created"
  rm -rf "$tmpdir"
}
test_cli_html_output

test_cli_pdf_output() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t pdf -o "$tmpdir/out" "$tmpdir/input.md" 2>&1)
  assert_contains "$out" "Generating" "Shows generating message"
  assert_file_exists "$tmpdir/out.pdf" "PDF file created"
  rm -rf "$tmpdir"
}
test_cli_pdf_output

test_cli_both_formats() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t pdf -t html -o "$tmpdir/out" "$tmpdir/input.md" 2>&1)
  assert_file_exists "$tmpdir/out.html" "HTML file created with -t pdf -t html"
  assert_file_exists "$tmpdir/out.pdf" "PDF file created with -t pdf -t html"
  rm -rf "$tmpdir"
}
test_cli_both_formats

test_cli_default_format_is_html() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -o "$tmpdir/out" "$tmpdir/input.md" 2>&1)
  assert_file_exists "$tmpdir/out.html" "Default format is HTML"
  [[ ! -f "$tmpdir/out.pdf" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "No PDF created when no -t pdf"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "No PDF created when no -t pdf"; ERRORS="${ERRORS}\n  FAIL: Unexpected PDF created"; }
  rm -rf "$tmpdir"
}
test_cli_default_format_is_html

test_cli_output_name_derived() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/myfile.md"
  out=$(cd "$tmpdir" && "$PANDIA" myfile.md 2>&1)
  assert_file_exists "$tmpdir/myfile.html" "Output name derived from input filename"
  rm -rf "$tmpdir"
}
test_cli_output_name_derived

section "cli: --maxwidth option"

test_cli_maxwidth() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  "$PANDIA" -t html -o "$tmpdir/out" --maxwidth 40em "$tmpdir/input.md" >/dev/null 2>&1
  local content
  content=$(cat "$tmpdir/out.html")
  assert_contains "$content" "40em" "Custom maxwidth appears in HTML output"
  rm -rf "$tmpdir"
}
test_cli_maxwidth

test_cli_maxwidth_default() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  "$PANDIA" -t html -o "$tmpdir/out" "$tmpdir/input.md" >/dev/null 2>&1
  local content
  content=$(cat "$tmpdir/out.html")
  assert_contains "$content" "60em" "Default maxwidth 60em in HTML output"
  rm -rf "$tmpdir"
}
test_cli_maxwidth_default

section "cli: --center-math option"

test_cli_center_math_html() {
  local tmpdir
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  "$PANDIA" -t html -o "$tmpdir/out" --center-math "$tmpdir/input.md" >/dev/null 2>&1
  local content
  content=$(cat "$tmpdir/out.html")
  assert_not_contains "$content" "displayAlign" "--center-math omits left-align MathJax config"
  rm -rf "$tmpdir"
}
test_cli_center_math_html

test_cli_default_left_align_math() {
  local tmpdir
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  "$PANDIA" -t html -o "$tmpdir/out" "$tmpdir/input.md" >/dev/null 2>&1
  local content
  content=$(cat "$tmpdir/out.html")
  assert_contains "$content" "displayAlign" "Default math is left-aligned (MathJax displayAlign)"
  rm -rf "$tmpdir"
}
test_cli_default_left_align_math

section "cli: --kroki-server option"

KROKI_AVAILABLE=false
if curl -sf --max-time 5 "https://kroki.io/health" >/dev/null 2>&1; then
  KROKI_AVAILABLE=true
fi

if $KROKI_AVAILABLE; then
  test_cli_kroki_server() {
    local tmpdir
    tmpdir=$(mktemp -d)
    printf '# Kroki\n\n```pikchr\nbox "A"; arrow; box "B"\n```\n' > "$tmpdir/input.md"
    cp "$FILTER" "$tmpdir/"
    local out
    out=$(cd "$tmpdir" && "$PANDIA" -t html -o "$tmpdir/out" --kroki-server https://kroki.io input.md 2>&1) || true
    assert_file_exists "$tmpdir/out.html" "--kroki-server produces HTML output"
    local content
    content=$(cat "$tmpdir/out.html" 2>/dev/null) || true
    assert_contains "$content" "kroki-" "--kroki-server renders kroki-only diagram type (pikchr)"
    rm -rf "$tmpdir"
  }
  test_cli_kroki_server
else
  printf "\n${BOLD}cli: --kroki-server option${RESET}\n"
  printf "  ${RED}SKIP${RESET} --kroki-server test: kroki.io not reachable\n"
fi

section "cli: --server flag"

# Test --server mode against a running container (if available)
if [[ -n "$CONTAINER_RT" ]]; then
  test_cli_server_flag() {
    local tmpdir port container_name
    tmpdir=$(mktemp -d)
    port=13399
    container_name="pandia-test-server-flag"
    echo '# Server mode test' > "$tmpdir/input.md"

    # Start server
    $CONTAINER_RT stop "$container_name" >/dev/null 2>&1 || true
    $CONTAINER_RT rm -f "$container_name" >/dev/null 2>&1 || true
    $CONTAINER_RT run --rm -d --name "$container_name" -p "${port}:${port}" \
      yaccob/pandia:latest pandia-serve "$port" >/dev/null 2>&1
    local i=0
    while [[ $i -lt 30 ]]; do
      curl -sf "http://localhost:${port}/health" >/dev/null 2>&1 && break
      sleep 1; i=$((i + 1))
    done

    # Render via --server
    local out
    out=$("$PANDIA" --server "http://localhost:${port}" -t html -o "$tmpdir/out" "$tmpdir/input.md" 2>&1) || true
    assert_file_exists "$tmpdir/out.html" "--server produces HTML output"

    # Cleanup
    $CONTAINER_RT stop "$container_name" >/dev/null 2>&1 || true
    rm -rf "$tmpdir"
  }
  test_cli_server_flag
else
  printf "\n${BOLD}cli: --server flag${RESET}\n"
  printf "  ${RED}SKIP${RESET} --server test: no container runtime found\n"
fi

print_summary
exit $FAIL
