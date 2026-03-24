#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

if [[ -z "$CONTAINER_RT" ]]; then
  printf "\n${BOLD}container entrypoint${RESET}\n"
  printf "  ${RED}SKIP${RESET} entrypoint tests: no container runtime found\n"
  exit 0
fi

section "container entrypoint"

test_entrypoint_help() {
  local out
  out=$($CONTAINER_RT run --rm yaccob/pandia --help 2>&1) || true
  assert_contains "$out" "Usage:" "Container --help shows usage"
  assert_contains "$out" "docker run" "Container --help shows docker examples"
}
test_entrypoint_help

test_entrypoint_no_input() {
  local out rc
  out=$($CONTAINER_RT run --rm yaccob/pandia 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "No input file" "Container: no input file error"
}
test_entrypoint_no_input

test_entrypoint_unknown_format() {
  local out rc
  out=$($CONTAINER_RT run --rm yaccob/pandia -t docx test.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "Unknown format" "Container: unknown format error"
  assert_exit_nonzero "$rc" "Container: non-zero exit for unknown format"
}
test_entrypoint_unknown_format

test_entrypoint_file_not_found() {
  local out rc
  out=$($CONTAINER_RT run --rm yaccob/pandia nonexistent.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "not found" "Container: file not found error"
  assert_exit_nonzero "$rc" "Container: non-zero exit for missing file"
}
test_entrypoint_file_not_found

test_entrypoint_html_render() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '# Container Test' > "$tmpdir/input.md"
  $CONTAINER_RT run --rm -v "$tmpdir:/data" yaccob/pandia -t html -o output.html input.md >/dev/null 2>&1 || true
  assert_file_exists "$tmpdir/output.html" "Container renders HTML with -o"
  local content
  content=$(cat "$tmpdir/output.html" 2>/dev/null) || true
  assert_contains "$content" "Container Test" "Container HTML has correct content"
  rm -rf "$tmpdir"
}
test_entrypoint_html_render

test_entrypoint_pdf_render() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '# Container PDF' > "$tmpdir/input.md"
  $CONTAINER_RT run --rm -v "$tmpdir:/data" yaccob/pandia -t pdf -o output.pdf input.md >/dev/null 2>&1 || true
  assert_file_exists "$tmpdir/output.pdf" "Container renders PDF with -o"
  rm -rf "$tmpdir"
}
test_entrypoint_pdf_render

test_entrypoint_stdout() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Stdout' > "$tmpdir/input.md"
  out=$($CONTAINER_RT run --rm -v "$tmpdir:/data" yaccob/pandia input.md 2>/dev/null) || true
  assert_contains "$out" "Stdout" "Container renders HTML to stdout by default"
  rm -rf "$tmpdir"
}
test_entrypoint_stdout

print_summary
exit $FAIL
