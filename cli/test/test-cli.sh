#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../test/helpers.sh"

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
  stdout=$("$PANDIA" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file") || true
  stderr=$(cat "$stderr_file")
  assert_contains "$stderr" "Generating" "Status message appears on stderr"
  assert_not_contains "$stdout" "Generating" "Status message not on stdout"
  rm -rf "$tmpdir"
}
test_cli_status_on_stderr

test_cli_stdout_html_without_output_flag() {
  local tmpdir stdout stderr_file stderr
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
  stderr=$(cat "$stderr_file")
  assert_contains "$stdout" "<h1" "HTML content appears on stdout without -o"
  assert_contains "$stderr" "Generating" "Status on stderr in stdout mode"
  rm -rf "$tmpdir"
}
test_cli_stdout_html_without_output_flag

test_cli_stdout_no_file_created() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$(cd "$tmpdir" && "$PANDIA" input.md 2>"$stderr_file") || true
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
  stdout=$("$PANDIA" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_file_exists "$tmpdir/out.html" "File created with -o"
  [[ -z "$stdout" ]] \
    && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "stdout empty with -o (content in file)"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "stdout empty with -o (content in file)"; ERRORS="${ERRORS}\n  FAIL: stdout not empty with -o"; }
  rm -rf "$tmpdir"
}
test_cli_file_mode_stdout_empty

test_cli_stdout_pdf_without_output_flag() {
  local tmpdir stderr_file stdout_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout_file="$tmpdir/stdout"
  "$PANDIA" -t pdf "$tmpdir/input.md" >"$stdout_file" 2>"$stderr_file" || true
  # PDF starts with %PDF magic bytes
  local header
  header=$(head -c 5 "$stdout_file")
  assert_contains "$header" "%PDF" "PDF content appears on stdout without -o"
  rm -rf "$tmpdir"
}
test_cli_stdout_pdf_without_output_flag

section "cli: local rendering (file mode)"

test_cli_html_file_output() {
  local tmpdir stderr_file stderr
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  "$PANDIA" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>"$stderr_file" >/dev/null
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
  "$PANDIA" -t pdf -o "$tmpdir/out.pdf" "$tmpdir/input.md" 2>"$stderr_file" >/dev/null
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
  stdout=$("$PANDIA" "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "<h1" "Default format is HTML (content on stdout)"
  rm -rf "$tmpdir"
}
test_cli_default_format_is_html

section "cli: --maxwidth option"

test_cli_maxwidth() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html --maxwidth 40em "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "40em" "Custom maxwidth appears in HTML output"
  rm -rf "$tmpdir"
}
test_cli_maxwidth

test_cli_maxwidth_default() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
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
  stdout=$("$PANDIA" -t html --center-math "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_not_contains "$stdout" "text-align:left" "--center-math omits left-align CSS"
  rm -rf "$tmpdir"
}
test_cli_center_math_html

test_cli_default_left_align_math() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "text-align:left" "Default math is left-aligned (CSS)"
  rm -rf "$tmpdir"
}
test_cli_default_left_align_math

test_cli_default_math_is_mathml() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
  assert_contains "$stdout" "<math" "Default math engine is MathML (not MathJax)"
  rm -rf "$tmpdir"
}
test_cli_default_math_is_mathml

test_cli_mathml_left_aligned() {
  local tmpdir stdout stderr_file
  tmpdir=$(mktemp -d)
  printf '# Math\n\n$$x^2$$\n' > "$tmpdir/input.md"
  stderr_file="$tmpdir/stderr"
  stdout=$("$PANDIA" -t html "$tmpdir/input.md" 2>"$stderr_file") || true
  if echo "$stdout" | grep -q 'math.*text-align.*left\|display.*block.*text-align.*left'; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} MathML display math has CSS left-alignment\n"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: MathML display math has CSS left-alignment"
    printf "  ${RED}FAIL${RESET} MathML display math has CSS left-alignment\n"
  fi
  rm -rf "$tmpdir"
}
test_cli_mathml_left_aligned

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
    out=$(cd "$tmpdir" && "$PANDIA" -t html -o "$tmpdir/out.html" --kroki-server https://kroki.io input.md 2>&1) || true
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
    out=$("$PANDIA" --server "http://localhost:${port}" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>&1) || true
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

section "cli: pandia-serve local (no container)"

PANDIA_SERVE="$(dirname "$PANDIA")/pandia-serve"

test_local_serve_renders() {
  local port=13398
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '# Local serve test' > "$tmpdir/input.md"

  # Start pandia-serve locally in background
  "$PANDIA_SERVE" "$port" &
  local serve_pid=$!
  local i=0
  while [[ $i -lt 30 ]]; do
    curl -sf "http://localhost:${port}/health" >/dev/null 2>&1 && break
    sleep 1; i=$((i + 1))
  done

  # Render via --server
  local out
  out=$("$PANDIA" --server "http://localhost:${port}" -t html -o "$tmpdir/out.html" "$tmpdir/input.md" 2>&1) || true

  # Must not fail with "cannot open filter" or similar
  assert_not_contains "$out" "No such file" \
    "pandia-serve local does not fail with missing filter"
  assert_not_contains "$out" "Error running filter" \
    "pandia-serve local filter runs without error"
  assert_file_exists "$tmpdir/out.html" \
    "pandia-serve local produces HTML output"

  # Cleanup
  kill "$serve_pid" 2>/dev/null; wait "$serve_pid" 2>/dev/null || true
  rm -rf "$tmpdir"
}
test_local_serve_renders

print_summary
exit $FAIL
