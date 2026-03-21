#!/usr/bin/env bash
# CLI integration test — verify example.md renders all diagram types
set -euo pipefail

HTML="${1:?Usage: $0 <example.html>}"
PASS=0
FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; RESET='\033[0m'

check_section() {
  local name="$1" pattern="${2:-<svg\|<img}"
  local has
  has=$(sed -n "/$name/,/^<h[0-9]/p" "$HTML" | grep -c "$pattern" || true)
  if [[ "$has" -gt 0 ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "$name"
  else
    FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "$name"
  fi
}

check_section "Sequence Diagram"
check_section "Class Diagram"
check_section "EBNF Syntax"
check_section "Directed Graph"
check_section "State Machine"
check_section "Flowchart"
check_section "Gantt Chart"
check_section "Ditaa"
check_section "TikZ"
check_section "Nomnoml"
check_section "DBML"
check_section "WaveDrom"
# Markmap uses inline HTML (not img/svg), check directly
has_mm=$(grep -c 'markmap-container' "$HTML" || true)
if [[ "$has_mm" -gt 0 ]]; then
  PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "Markmap"
else
  FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Markmap"
fi

printf "\nResults: "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All $PASS sections rendered${RESET}\n"
else
  printf "${RED}$FAIL missing${RESET}, $PASS rendered\n"
  exit 1
fi
