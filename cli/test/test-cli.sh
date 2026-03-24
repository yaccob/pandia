#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

# --- Start a local server for all rendering tests ---
SERVE_PORT=13398
PANDIA_SERVE="$(dirname "$PANDIA")/pandia-serve"

"$PANDIA_SERVE" "$SERVE_PORT" &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf "http://localhost:${SERVE_PORT}/health" >/dev/null 2>&1 && break
  sleep 0.5
done

SERVER_URL="http://localhost:${SERVE_PORT}"

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

test_cli_duplicate_format() {
  local tmpdir out rc
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t html -t pdf "$tmpdir/input.md" 2>&1) && rc=0 || rc=$?
  assert_exit_nonzero "$rc" "Duplicate -t causes error"
  assert_contains "$out" "-t" "Error mentions -t flag"
  rm -rf "$tmpdir"
}
test_cli_duplicate_format

test_cli_watch_requires_output() {
  local tmpdir out rc
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" --watch "$tmpdir/input.md" 2>&1) && rc=0 || rc=$?
  assert_exit_nonzero "$rc" "--watch without -o exits with error"
  assert_contains "$out" "-o" "Error message mentions -o"
  rm -rf "$tmpdir"
}
test_cli_watch_requires_output

section "cli: stdout/stderr convention"

test_cli_status_on_stderr() {
  local tmpdir stdout stderr_file stderr
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file") || true
  stderr=$(cat "$stderr_file")
  assert_contains "$stderr" "Generating" "Status message appears on stderr"
  assert_not_contains "$stdout" "Generating" "Status message not on stdout"
  rm -rf "$tmpdir"
}
test_cli_status_on_stderr

test_cli_stdout_html() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "Hello" "HTML content appears on stdout without -o"
  rm -rf "$tmpdir"
}
test_cli_stdout_html

test_cli_stdout_no_file_created() {
  local tmpdir stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  "$PANDIA" --server "$SERVER_URL" "$tmpdir/input.md" >"$tmpdir/stdout" 2>"$stderr_file" || true
  [[ ! -f "$tmpdir/input.html" ]] \
    && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "No file created without -o"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "No file created without -o"; ERRORS="${ERRORS}\n  FAIL: Unexpected file created without -o"; }
  rm -rf "$tmpdir"
}
test_cli_stdout_no_file_created

test_cli_file_mode_stdout_empty() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_file_exists "$tmpdir/out.html" "File created with -o"
  [[ -z "$stdout" ]] \
    && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "stdout empty with -o (content in file)"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "stdout empty with -o (content in file)"; ERRORS="${ERRORS}\n  FAIL: stdout not empty with -o"; }
  rm -rf "$tmpdir"
}
test_cli_file_mode_stdout_empty

test_cli_stdout_pdf() {
  local tmpdir stderr_file stdout_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout_file="$tmpdir/stdout"
  "$PANDIA" --server "$SERVER_URL" -t pdf "$tmpdir/input.md" >"$stdout_file" 2>"$stderr_file" || true
  local header
  header=$(head -c 5 "$stdout_file")
  assert_contains "$header" "%PDF" "PDF content appears on stdout without -o"
  rm -rf "$tmpdir"
}
test_cli_stdout_pdf

section "cli: file output"

test_cli_html_file_output() {
  local tmpdir stderr_file stderr
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  "$PANDIA" --server "$SERVER_URL" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file" >/dev/null
  stderr=$(cat "$stderr_file")
  assert_contains "$stderr" "Generating" "Shows generating message on stderr"
  assert_file_exists "$tmpdir/out.html" "HTML file created"
  rm -rf "$tmpdir"
}
test_cli_html_file_output

test_cli_pdf_file_output() {
  local tmpdir stderr_file stderr
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  "$PANDIA" --server "$SERVER_URL" -t pdf -o "$tmpdir/out.pdf" "$tmpdir/input.md" 2>"$stderr_file" >/dev/null
  stderr=$(cat "$stderr_file")
  assert_contains "$stderr" "Generating" "Shows generating message on stderr"
  assert_file_exists "$tmpdir/out.pdf" "PDF file created"
  rm -rf "$tmpdir"
}
test_cli_pdf_file_output

test_cli_default_format_is_html() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "Hello" "Default format is HTML (content on stdout)"
  rm -rf "$tmpdir"
}
test_cli_default_format_is_html

section "cli: --maxwidth option"

test_cli_maxwidth() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" --maxwidth 40em "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "40em" "Custom maxwidth appears in HTML output"
  rm -rf "$tmpdir"
}
test_cli_maxwidth

test_cli_maxwidth_default() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "60em" "Default maxwidth 60em in HTML output"
  rm -rf "$tmpdir"
}
test_cli_maxwidth_default

section "cli: --center-math option"

test_cli_center_math_html() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" --center-math "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_not_contains "$stdout" "text-align:left" "--center-math omits left-align CSS"
  rm -rf "$tmpdir"
}
test_cli_center_math_html

test_cli_default_left_align_math() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "text-align:left" "Default math is left-aligned (CSS)"
  rm -rf "$tmpdir"
}
test_cli_default_left_align_math

test_cli_default_math_is_mathml() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" --server "$SERVER_URL" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "<math" "Default math engine is MathML (not MathJax)"
  rm -rf "$tmpdir"
}
test_cli_default_math_is_mathml

section "cli: connection error"

test_cli_no_server() {
  local tmpdir out rc
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" --server http://localhost:19999 "$tmpdir/input.md" 2>&1) && rc=0 || rc=$?
  assert_exit_nonzero "$rc" "Non-zero exit when server unreachable"
  assert_contains "$out" "Cannot connect" "Error mentions connection failure"
  rm -rf "$tmpdir"
}
test_cli_no_server

print_summary
exit $FAIL
