#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# pandia test runner — dir-block tests (Phase 1)
# Usage: bash test/test.sh [filter-path]
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="${1:-$PROJECT_DIR/diagram-filter.lua}"

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: Filter not found: $FILTER" >&2
  exit 1
fi

PASS=0
FAIL=0
ERRORS=""

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; BOLD=''; RESET=''
fi

# --- Assertions -------------------------------------------------------

assert_contains() {
  local output="$1" pattern="$2" msg="$3"
  if echo "$output" | grep -qF -- "$pattern"; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${msg} (expected pattern: ${pattern})"
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "       expected pattern: %s\n" "$pattern"
  fi
}

assert_not_contains() {
  local output="$1" pattern="$2" msg="$3"
  if echo "$output" | grep -qF -- "$pattern"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${msg} (unexpected pattern found: ${pattern})"
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "       unexpected pattern found: %s\n" "$pattern"
  else
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  fi
}

assert_count() {
  local output="$1" pattern="$2" expected="$3" msg="$4"
  local actual
  actual=$(echo "$output" | grep -oF -- "$pattern" | wc -l | tr -d ' ')
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${msg} (expected ${expected}, got ${actual})"
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "       expected %s occurrences, got %s\n" "$expected" "$actual"
  fi
}

# --- Helper -----------------------------------------------------------

WORK_DIR=""

setup_workdir() {
  WORK_DIR=$(mktemp -d)
  cp "$FILTER" "$WORK_DIR/"
}

teardown_workdir() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  WORK_DIR=""
}

run_filter() {
  local input="$1"
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html 2>/dev/null
}

run_filter_stderr() {
  local input="$1"
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html 2>&1 >/dev/null
}

# Run filter in isolated workdir (for diagram types that produce files)
run_filter_isolated() {
  local input="$1"
  setup_workdir
  (cd "$WORK_DIR" && echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html 2>/dev/null)
  local rc=$?
  teardown_workdir
  return $rc
}

run_filter_isolated_stderr() {
  local input="$1"
  setup_workdir
  (cd "$WORK_DIR" && echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html 2>&1 >/dev/null)
  local rc=$?
  teardown_workdir
  return $rc
}

# Run filter in isolated workdir, keep both stdout and stderr
run_filter_isolated_both() {
  local input="$1"
  setup_workdir
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr")
  LAST_STDOUT=$(cat "$tmpout")
  LAST_STDERR=$(cat "$tmperr")
  teardown_workdir
}

# --- Tests: Happy Path ------------------------------------------------

section() {
  printf "\n${BOLD}%s${RESET}\n" "$1"
}

section "dir-block: basic SVG generation"

test_basic_tree() {
  local input='```dir
root
  child1
  child2
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "<svg" "SVG element generated"
  assert_contains "$out" "</svg>" "SVG properly closed"
  assert_contains "$out" "<text" "Text elements present"
  assert_contains "$out" "<line" "Line elements present"
  assert_count "$out" "<text " 3 "3 text elements (root + 2 children)"
}
test_basic_tree

test_root_only() {
  local input='```dir
singlefile
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "<svg" "SVG generated for single entry"
  assert_count "$out" "<text " 1 "Exactly 1 text element"
  assert_not_contains "$out" "<line" "No lines for single entry"
}
test_root_only

test_deep_nesting() {
  local input='```dir
a
  b
    c
      d
        e
```'
  local out
  out=$(run_filter "$input")
  assert_count "$out" "<text " 5 "5 text elements for 5-level tree"
  assert_contains "$out" "<line" "Lines present for deep tree"
}
test_deep_nesting

# --- Tests: Directory detection & bold --------------------------------

section "dir-block: directory detection and bold rendering"

test_trailing_slash_bold() {
  local input='```dir
project
  src/
  README.md
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" 'font-weight="bold"' "Trailing slash dir is bold"
  assert_not_contains "$out" ">src/<" "Trailing slash not displayed"
  assert_contains "$out" ">src<" "Dir name without slash"
}
test_trailing_slash_bold

test_children_make_parent_bold() {
  local input='```dir
project
  src
    main.lua
  README.md
```'
  local out
  out=$(run_filter "$input")
  # src has children → bold; project has children → bold
  # Count bold: project, src = 2
  assert_count "$out" 'font-weight="bold"' 2 "Parent dirs auto-detected as bold (project, src)"
}
test_children_make_parent_bold

test_empty_dir_slash() {
  local input='```dir
project
  empty/
  file.txt
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" 'font-weight="bold"' "Empty dir with slash is bold"
  assert_contains "$out" ">empty<" "Empty dir name without slash"
}
test_empty_dir_slash

# --- Tests: Edge cases ------------------------------------------------

section "dir-block: edge cases"

test_whitespace_lines_ignored() {
  local input='```dir
root

  child1

  child2
```'
  local out
  out=$(run_filter "$input")
  assert_count "$out" "<text " 3 "Whitespace lines ignored, 3 entries"
}
test_whitespace_lines_ignored

test_special_characters_escaped() {
  local input='```dir
project
  a&b.txt
  <script>.js
  file>name
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "&amp;" "Ampersand escaped"
  assert_contains "$out" "&lt;" "Less-than escaped"
  assert_contains "$out" "&gt;" "Greater-than escaped"
}
test_special_characters_escaped

test_single_child() {
  local input='```dir
root
  only-child
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "<svg" "SVG generated"
  assert_count "$out" "<text " 2 "2 text elements"
  assert_contains "$out" "<line" "Connector lines present"
}
test_single_child

test_long_filename() {
  local input='```dir
root
  this-is-a-very-long-filename-that-should-still-render-correctly.txt
```'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "this-is-a-very-long-filename" "Long filename rendered"
}
test_long_filename

test_tab_indentation() {
  local input
  input=$(printf '```dir\nroot\n\tchild1\n\tchild2\n```')
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "<svg" "Tab indentation produces SVG"
  assert_count "$out" "<text " 3 "3 entries with tab indent"
}
test_tab_indentation

# --- Tests: Error cases -----------------------------------------------

section "dir-block: error cases"

test_empty_block() {
  local input='```dir
```'
  local err
  err=$(run_filter_stderr "$input")
  assert_contains "$err" "Empty dir block" "Empty block error message"
}
test_empty_block

test_whitespace_only_block() {
  local input='```dir


```'
  local err
  err=$(run_filter_stderr "$input")
  assert_contains "$err" "Empty dir block" "Whitespace-only block error"
}
test_whitespace_only_block

test_indentation_less_than_root() {
  local input='```dir
    root
  child
```'
  local err
  err=$(run_filter_stderr "$input")
  assert_contains "$err" "indentation is less than the root" "Negative indent error"
}
test_indentation_less_than_root

test_inconsistent_indentation() {
  local input='```dir
root
  child1
   child2
```'
  local err
  err=$(run_filter_stderr "$input")
  assert_contains "$err" "inconsistent indentation" "Inconsistent indent error"
}
test_inconsistent_indentation

test_level_jump() {
  local input='```dir
root
  child
      grandgrandchild
```'
  local err
  err=$(run_filter_stderr "$input")
  assert_contains "$err" "jumps by more than one level" "Level jump error"
}
test_level_jump

# --- Tests: PlantUML --------------------------------------------------

section "plantuml: happy path"

test_plantuml_basic() {
  local input='```plantuml
@startuml
Alice -> Bob: hello
@enduml
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "PlantUML generates image element"
  assert_contains "$out" "plantuml-" "Image uses plantuml prefix"
  assert_contains "$out" ".svg" "HTML output uses SVG"
}
test_plantuml_basic

section "plantuml: error cases"

test_plantuml_invalid_syntax() {
  local input='```plantuml
@startuml
this is not valid plantuml syntax %%%
@enduml
```'
  run_filter_isolated_both "$input"
  # PlantUML still generates an SVG with an error image, so we check stderr
  # Currently there may be no stderr — this test documents current behavior
  # and will be updated when we add error handling
  assert_contains "$LAST_STDOUT" "<img" "PlantUML produces output even on syntax error (error diagram)"
}
test_plantuml_invalid_syntax

# --- Tests: Graphviz --------------------------------------------------

section "graphviz: happy path"

test_graphviz_basic() {
  local input='```graphviz
digraph { A -> B; }
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "Graphviz generates image element"
  assert_contains "$out" "graphviz-" "Image uses graphviz prefix"
  assert_contains "$out" ".svg" "HTML output uses SVG"
}
test_graphviz_basic

test_dot_alias() {
  local input='```dot
digraph { X -> Y; }
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "dot alias generates image element"
  assert_contains "$out" "graphviz-" "dot alias uses graphviz prefix"
}
test_dot_alias

section "graphviz: error cases"

test_graphviz_invalid_syntax() {
  local input='```graphviz
this is not valid dot
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "graphviz error" "Graphviz error shown in output"
  assert_contains "$LAST_STDOUT" "rendering failed" "Graphviz failure message in output"
  assert_contains "$LAST_STDERR" "graphviz error" "Graphviz error on stderr"
}
test_graphviz_invalid_syntax

# --- Tests: Mermaid ---------------------------------------------------

section "mermaid: happy path"

test_mermaid_basic() {
  local input='```mermaid
graph LR
  A --> B
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "Mermaid generates image element"
  assert_contains "$out" "mermaid-" "Image uses mermaid prefix"
}
test_mermaid_basic

section "mermaid: error cases"

test_mermaid_invalid_syntax() {
  local input='```mermaid
this is not a valid mermaid diagram @@@
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "mermaid error" "Mermaid error shown in output"
  assert_contains "$LAST_STDOUT" "rendering failed" "Mermaid failure message in output"
  assert_contains "$LAST_STDERR" "mermaid error" "Mermaid error on stderr"
}
test_mermaid_invalid_syntax

# --- Tests: TikZ ------------------------------------------------------

section "tikz: happy path"

test_tikz_basic() {
  local input='```tikz
\draw (0,0) -- (1,1);
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "TikZ generates image element"
  assert_contains "$out" "tikz-" "Image uses tikz prefix"
}
test_tikz_basic

section "tikz: error cases"

test_tikz_invalid_syntax() {
  local input='```tikz
\this_is_not_valid_latex
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "tikz error" "TikZ error shown in output"
  assert_contains "$LAST_STDOUT" "rendering failed" "TikZ failure message in output"
  assert_contains "$LAST_STDERR" "tikz error" "TikZ error on stderr"
}
test_tikz_invalid_syntax

# --- Tests: Unknown diagram type --------------------------------------

section "unknown diagram type"

test_unknown_type_ignored() {
  local input='```nosuchdiagram
some content
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_not_contains "$out" "<img" "Unknown type produces no image"
  assert_contains "$out" "nosuchdiagram" "Unknown type preserved as code block"
}
test_unknown_type_ignored

# --- Tests: CLI (bin/pandia) ------------------------------------------

PANDIA="$PROJECT_DIR/bin/pandia"

section "cli: version and help"

test_cli_version_long() {
  local out
  out=$("$PANDIA" --version 2>&1)
  assert_contains "$out" "pandia v" "--version shows version string"
  assert_contains "$out" "1.4.0" "--version shows correct version number"
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
  assert_contains "$out" "--serve" "--help documents --serve"
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
  [[ $rc -ne 0 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Non-zero exit code"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Non-zero exit code"; ERRORS="${ERRORS}\n  FAIL: Non-zero exit code (got 0)"; }
}
test_cli_no_input

test_cli_file_not_found() {
  local out rc
  out=$("$PANDIA" -t html /nonexistent/file.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "not found" "File not found error message"
  [[ $rc -ne 0 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Non-zero exit code"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Non-zero exit code"; ERRORS="${ERRORS}\n  FAIL: Non-zero exit code (got 0)"; }
}
test_cli_file_not_found

test_cli_unknown_format() {
  local out rc
  out=$("$PANDIA" -t docx test.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "Unknown format" "Unknown format error message"
  assert_contains "$out" "docx" "Error includes the bad format name"
  [[ $rc -ne 0 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Non-zero exit code"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Non-zero exit code"; ERRORS="${ERRORS}\n  FAIL: Non-zero exit code (got 0)"; }
}
test_cli_unknown_format

test_cli_kroki_no_env() {
  local out rc
  out=$(PANDIA_KROKI_URL="" "$PANDIA" --kroki test.md 2>&1) && rc=0 || rc=$?
  assert_contains "$out" "PANDIA_KROKI_URL" "--kroki without env var mentions the variable"
  [[ $rc -ne 0 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Non-zero exit code"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Non-zero exit code"; ERRORS="${ERRORS}\n  FAIL: Non-zero exit code (got 0)"; }
}
test_cli_kroki_no_env

section "cli: local rendering"

test_cli_html_output() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t html -o "$tmpdir/out" --local "$tmpdir/input.md" 2>&1)
  assert_contains "$out" "Generating" "Shows generating message"
  [[ -f "$tmpdir/out.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "HTML file created"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "HTML file created"; ERRORS="${ERRORS}\n  FAIL: HTML file not created"; }
  rm -rf "$tmpdir"
}
test_cli_html_output

test_cli_pdf_output() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t pdf -o "$tmpdir/out" --local "$tmpdir/input.md" 2>&1)
  assert_contains "$out" "Generating" "Shows generating message"
  [[ -f "$tmpdir/out.pdf" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "PDF file created"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "PDF file created"; ERRORS="${ERRORS}\n  FAIL: PDF file not created"; }
  rm -rf "$tmpdir"
}
test_cli_pdf_output

test_cli_both_formats() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -t pdf -t html -o "$tmpdir/out" --local "$tmpdir/input.md" 2>&1)
  local ok=true
  [[ -f "$tmpdir/out.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "HTML file created with -t pdf -t html"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "HTML file created with -t pdf -t html"; ERRORS="${ERRORS}\n  FAIL: HTML file not created"; }
  [[ -f "$tmpdir/out.pdf" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "PDF file created with -t pdf -t html"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "PDF file created with -t pdf -t html"; ERRORS="${ERRORS}\n  FAIL: PDF file not created"; }
  rm -rf "$tmpdir"
}
test_cli_both_formats

test_cli_default_format_is_html() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/input.md"
  out=$("$PANDIA" -o "$tmpdir/out" --local "$tmpdir/input.md" 2>&1)
  [[ -f "$tmpdir/out.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Default format is HTML"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Default format is HTML"; ERRORS="${ERRORS}\n  FAIL: Default HTML not created"; }
  [[ ! -f "$tmpdir/out.pdf" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "No PDF created when no -t pdf"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "No PDF created when no -t pdf"; ERRORS="${ERRORS}\n  FAIL: Unexpected PDF created"; }
  rm -rf "$tmpdir"
}
test_cli_default_format_is_html

test_cli_output_name_derived() {
  local tmpdir out
  tmpdir=$(mktemp -d)
  echo '# Hello' > "$tmpdir/myfile.md"
  out=$(cd "$tmpdir" && "$PANDIA" --local myfile.md 2>&1)
  [[ -f "$tmpdir/myfile.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Output name derived from input filename"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Output name derived from input filename"; ERRORS="${ERRORS}\n  FAIL: myfile.html not created"; }
  rm -rf "$tmpdir"
}
test_cli_output_name_derived

# --- Tests: CLI --watch -----------------------------------------------

section "cli: --watch mode"

kill_watch() {
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null || true
}

test_cli_watch_initial_build() {
  local tmpdir pid
  tmpdir=$(mktemp -d)
  echo '# Initial' > "$tmpdir/input.md"

  "$PANDIA" --watch --local -t html -o "$tmpdir/out" "$tmpdir/input.md" > "$tmpdir/watch.log" 2>&1 &
  pid=$!

  # Wait for initial build (up to 10s)
  local i=0
  while [[ $i -lt 20 && ! -f "$tmpdir/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  [[ -f "$tmpdir/out.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "--watch performs initial build"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "--watch performs initial build"; ERRORS="${ERRORS}\n  FAIL: --watch initial build: out.html not created within 10s"; }

  assert_contains "$(cat "$tmpdir/watch.log")" "Watching" "Watch mode shows watching message"

  kill_watch "$pid"
  rm -rf "$tmpdir"
}
test_cli_watch_initial_build

test_cli_watch_rebuilds_on_change() {
  local tmpdir pid
  tmpdir=$(mktemp -d)
  echo '# Version 1' > "$tmpdir/input.md"

  "$PANDIA" --watch --local -t html -o "$tmpdir/out" "$tmpdir/input.md" > "$tmpdir/watch.log" 2>&1 &
  pid=$!

  # Wait for initial build
  local i=0
  while [[ $i -lt 20 && ! -f "$tmpdir/out.html" ]]; do
    sleep 0.5; i=$((i + 1))
  done

  # Record initial file timestamp
  local ts_before
  ts_before=$(stat -f%m "$tmpdir/out.html" 2>/dev/null || stat -c%Y "$tmpdir/out.html" 2>/dev/null)

  # Wait a moment so the poll cycle picks up the current hash
  sleep 2

  # Modify source file
  echo '# Version 2 — changed content' > "$tmpdir/input.md"

  # Wait for rebuild (up to 10s)
  local rebuilt=false
  i=0
  while [[ $i -lt 20 ]]; do
    sleep 0.5; i=$((i + 1))
    local ts_after
    ts_after=$(stat -f%m "$tmpdir/out.html" 2>/dev/null || stat -c%Y "$tmpdir/out.html" 2>/dev/null)
    if [[ "$ts_after" != "$ts_before" ]]; then
      rebuilt=true
      break
    fi
  done

  $rebuilt && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "--watch rebuilds after source change"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "--watch rebuilds after source change"; ERRORS="${ERRORS}\n  FAIL: --watch did not rebuild within 10s after source change"; }

  assert_contains "$(cat "$tmpdir/watch.log")" "Change detected" "Watch log shows change detected"

  # Verify new content is in output
  assert_contains "$(cat "$tmpdir/out.html")" "Version 2" "Rebuilt output contains new content"

  kill_watch "$pid"
  rm -rf "$tmpdir"
}
test_cli_watch_rebuilds_on_change

# --- Tests: CLI --serve -----------------------------------------------

# --serve requires a running container; detect container runtime
CONTAINER_RT=""
if command -v podman >/dev/null 2>&1; then
  CONTAINER_RT="podman"
elif command -v docker >/dev/null 2>&1; then
  CONTAINER_RT="docker"
fi

SERVE_PORT=13300
SERVE_CONTAINER="pandia-test-serve"
SERVE_TMPDIR=""

start_serve() {
  # Clean up any leftover container from previous run
  $CONTAINER_RT stop "$SERVE_CONTAINER" >/dev/null 2>&1 || true
  $CONTAINER_RT rm -f "$SERVE_CONTAINER" >/dev/null 2>&1 || true

  SERVE_TMPDIR=$(mktemp -d)
  echo '# Serve Test' > "$SERVE_TMPDIR/test-serve.md"

  $CONTAINER_RT run --rm -d --name "$SERVE_CONTAINER" \
    -p "${SERVE_PORT}:${SERVE_PORT}" \
    -v "$SERVE_TMPDIR:/data" \
    yaccob/pandia --serve "$SERVE_PORT" >/dev/null 2>&1

  # Wait for server to be ready (poll /health, up to 30s)
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

if [[ -n "$CONTAINER_RT" ]]; then
  section "cli: --serve mode (container: $CONTAINER_RT)"

  if start_serve; then

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
      sleep 1  # wait for volume sync
      [[ -f "$SERVE_TMPDIR/test-serve.html" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "HTML file created by server"; } \
        || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "HTML file created by server"; ERRORS="${ERRORS}\n  FAIL: test-serve.html not found"; }
    }
    test_serve_render_html

    test_serve_render_pdf() {
      local out
      out=$(curl -s -X POST "http://localhost:${SERVE_PORT}/render" \
        -d "file=test-serve.md&to=pdf" 2>&1) || true
      assert_contains "$out" '"ok":true' "/render PDF returns ok:true"
      sleep 1
      [[ -f "$SERVE_TMPDIR/test-serve.pdf" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "PDF file created by server"; } \
        || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "PDF file created by server"; ERRORS="${ERRORS}\n  FAIL: test-serve.pdf not found"; }
    }
    test_serve_render_pdf

    test_serve_render_both() {
      # Clean previous outputs
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

    stop_serve
  else
    printf "  ${RED}SKIP${RESET} --serve tests: container failed to start\n"
    stop_serve
  fi
else
  printf "\n${BOLD}cli: --serve mode${RESET}\n"
  printf "  ${RED}SKIP${RESET} --serve tests: no container runtime (docker/podman) found\n"
fi

# --- Summary ----------------------------------------------------------

printf "\n${BOLD}Results:${RESET} "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All %d tests passed${RESET}\n" "$PASS"
else
  printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$FAIL" "$PASS"
  printf "\nFailures:${ERRORS}\n"
fi

exit $FAIL
