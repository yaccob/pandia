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
  if echo "$output" | grep -q "$pattern"; then
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
  if echo "$output" | grep -q "$pattern"; then
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
  actual=$(echo "$output" | grep -o "$pattern" | wc -l | tr -d ' ')
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

# --- Summary ----------------------------------------------------------

printf "\n${BOLD}Results:${RESET} "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All %d tests passed${RESET}\n" "$PASS"
else
  printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$FAIL" "$PASS"
  printf "\nFailures:${ERRORS}\n"
fi

exit $FAIL
