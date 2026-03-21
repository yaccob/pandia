#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# pandia test runner — runs all test modules
# Usage: bash test/test.sh [filter-path]
#
# Individual modules can be run separately:
#   bash test/test-dir.sh
#   bash test/test-diagrams.sh
#   bash test/test-cli.sh
#   ...
# -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pass filter path via env var so modules pick it up
export PANDIA_TEST_FILTER="${1:-}"

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_ERRORS=""
FAILED_MODULES=""

# Colors
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; BOLD=''; RESET=''
fi

run_module() {
  local module="$1"
  local name
  name=$(basename "$module" .sh)

  printf "\n${BOLD}═══ %s ═══${RESET}\n" "$name"

  local output rc
  output=$(bash "$module" 2>&1) && rc=0 || rc=$?
  echo "$output"

  # Parse results from last line
  local pass fail
  pass=$(echo "$output" | grep -oE '[0-9]+ tests passed' | grep -oE '[0-9]+' || echo 0)
  fail=$(echo "$output" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | head -1 || echo 0)

  if [[ -z "$pass" || "$pass" -eq 0 ]]; then
    # Try alternative: "N failed, M passed"
    pass=$(echo "$output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
  fi

  TOTAL_PASS=$((TOTAL_PASS + ${pass:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${fail:-0}))

  if [[ $rc -ne 0 ]]; then
    FAILED_MODULES="${FAILED_MODULES} ${name}"
  fi
}

MODULES=(
  "$SCRIPT_DIR/test-dir.sh"
  "$SCRIPT_DIR/test-diagrams.sh"
  "$SCRIPT_DIR/test-kroki.sh"
  "$SCRIPT_DIR/test-robustness.sh"
  "$SCRIPT_DIR/test-cli.sh"
  "$SCRIPT_DIR/test-watch.sh"
  "$SCRIPT_DIR/test-container.sh"
  "$SCRIPT_DIR/test-entrypoint.sh"
)

for module in "${MODULES[@]}"; do
  if [[ -f "$module" ]]; then
    run_module "$module"
  else
    printf "\n${RED}Module not found: %s${RESET}\n" "$module"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
done

# --- Grand total ------------------------------------------------------

printf "\n${BOLD}══════════════════════════════════${RESET}\n"
printf "${BOLD}Grand total:${RESET} "
if [[ $TOTAL_FAIL -eq 0 ]]; then
  printf "${GREEN}All %d tests passed${RESET}\n" "$TOTAL_PASS"
else
  printf "${RED}%d failed${RESET}, ${GREEN}%d passed${RESET}\n" "$TOTAL_FAIL" "$TOTAL_PASS"
  printf "Failed modules:${FAILED_MODULES}\n"
fi

[[ $TOTAL_FAIL -eq 0 ]]
