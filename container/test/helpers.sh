#!/usr/bin/env bash
# -------------------------------------------------------------------
# Container test helpers — assertions and utilities
# Sourced by container test modules; not meant to be run directly.
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$CONTAINER_DIR/.." && pwd)"

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

# Detect container runtime
CONTAINER_RT=""
if command -v podman >/dev/null 2>&1; then
  CONTAINER_RT="podman"
elif command -v docker >/dev/null 2>&1; then
  CONTAINER_RT="docker"
fi

# --- Summary ----------------------------------------------------------

print_summary() {
  printf "\n${BOLD}Results:${RESET} "
  if [[ $FAIL -eq 0 ]]; then
    printf "${GREEN}All %d tests passed${RESET}\n" "$PASS"
  else
    printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$FAIL" "$PASS"
    printf "\nFailures:${ERRORS}\n"
  fi
}
