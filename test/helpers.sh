#!/usr/bin/env bash
# -------------------------------------------------------------------
# pandia test helpers — shared assertions, runners, and utilities
# Sourced by test modules; not meant to be run directly.
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILTER="${PANDIA_TEST_FILTER:-$PROJECT_DIR/diagram-filter.lua}"
PANDIA="$PROJECT_DIR/bin/pandia"

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

assert_exit_nonzero() {
  local rc="$1" msg="$2"
  [[ $rc -ne 0 ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "$msg"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "$msg"; ERRORS="${ERRORS}\n  FAIL: ${msg} (got exit 0)"; }
}

assert_file_exists() {
  local path="$1" msg="$2"
  [[ -f "$path" ]] && { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "$msg"; } \
    || { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "$msg"; ERRORS="${ERRORS}\n  FAIL: ${msg} (file not found)"; }
}

section() {
  printf "\n${BOLD}%s${RESET}\n" "$1"
}

# --- Helpers ----------------------------------------------------------

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

# Run filter targeting PDF (latex output) in isolated workdir.
# WORK_DIR is preserved — caller must call teardown_workdir.
run_filter_pdf_keep() {
  local input="$1"
  setup_workdir
  (cd "$WORK_DIR" && echo "$input" | pandoc --lua-filter=diagram-filter.lua \
    --from=gfm+tex_math_dollars --to=latex 2>/dev/null) || true
}

run_filter_kroki() {
  local input="$1" url="$2"
  setup_workdir
  (cd "$WORK_DIR" && export PANDIA_KROKI_URL="$url" && \
    echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html 2>/dev/null)
  local rc=$?
  teardown_workdir
  return $rc
}

run_filter_kroki_both() {
  local input="$1" url="$2"
  setup_workdir
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && export PANDIA_KROKI_URL="$url" && \
    echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr") || true
  LAST_STDOUT=$(cat "$tmpout")
  LAST_STDERR=$(cat "$tmperr")
  teardown_workdir
}

run_filter_kroki_pdf_keep() {
  local input="$1" url="$2"
  setup_workdir
  (cd "$WORK_DIR" && export PANDIA_KROKI_URL="$url" && \
    echo "$input" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t latex 2>/dev/null) || true
}

# Detect container runtime
CONTAINER_RT=""
if command -v podman >/dev/null 2>&1; then
  CONTAINER_RT="podman"
elif command -v docker >/dev/null 2>&1; then
  CONTAINER_RT="docker"
fi

# --- Summary helper (called at end of each module) --------------------

print_summary() {
  printf "\n${BOLD}Results:${RESET} "
  if [[ $FAIL -eq 0 ]]; then
    printf "${GREEN}All %d tests passed${RESET}\n" "$PASS"
  else
    printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$FAIL" "$PASS"
    printf "\nFailures:${ERRORS}\n"
  fi
}
