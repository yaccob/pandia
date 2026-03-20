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

run_filter() {
  local input="$1"
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html 2>/dev/null
}

run_filter_stderr() {
  local input="$1"
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html 2>&1 >/dev/null
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

# --- Summary ----------------------------------------------------------

printf "\n${BOLD}Results:${RESET} "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All %d tests passed${RESET}\n" "$PASS"
else
  printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$FAIL" "$PASS"
  printf "\nFailures:${ERRORS}\n"
fi

exit $FAIL
