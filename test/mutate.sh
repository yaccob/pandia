#!/usr/bin/env bash
# Mutation testing — apply random mutations to source files, run tests,
# and report which mutations survive (= test gaps).
#
# Usage: bash test/mutate.sh [ROUNDS]
#   ROUNDS  Number of mutation attempts (default: 50)
#
# Each round:
#   1. Pick a random source file
#   2. Pick a random code line
#   3. Apply a random mutation
#   4. Syntax-check the mutated file — skip if syntax error
#   5. Run make test-quick — if tests still pass, the mutant survived
#   6. Restore the original file
#
# Output: summary of survived mutants (= test gaps to investigate)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

ROUNDS="${1:-50}"

# --- Mutable source files and their syntax checkers ---

# file:checker pairs — checker must exit 0 for valid syntax
declare -A SYNTAX_CHECK
SYNTAX_CHECK["bin/pandia"]="sh -n"
SYNTAX_CHECK["bin/pandia-serve"]="sh -n"
SYNTAX_CHECK["entrypoint.sh"]="sh -n"
SYNTAX_CHECK["diagram-filter.lua"]="luac -p"
SYNTAX_CHECK["pandia-server.mjs"]="node --check"
SYNTAX_CHECK["diagram-renderer.mjs"]="node --check"
SYNTAX_CHECK["markmap-render.mjs"]="node --check"
SYNTAX_CHECK["mermaid-server.mjs"]="node --check"

FILES=("${!SYNTAX_CHECK[@]}")

# --- Mutation operators ---

mutate_line() {
  local line="$1"
  local result=""

  # Collect applicable mutations, then pick one at random
  local -a candidates=()

  # Always available: delete the line
  candidates+=("delete")

  # Conditional mutations — only offer if the pattern exists
  echo "$line" | grep -q 'true'    && candidates+=("true_false")
  echo "$line" | grep -q 'false'   && candidates+=("false_true")
  echo "$line" | grep -q '==='     && candidates+=("strict_eq_neq")
  echo "$line" | grep -q '!=='     && candidates+=("strict_neq_eq")
  echo "$line" | grep -q '=='      && candidates+=("eq_neq")
  echo "$line" | grep -q '!='      && candidates+=("neq_eq")
  echo "$line" | grep -q ' = '     && candidates+=("assign_neq")
  echo "$line" | grep -q '&&'      && candidates+=("and_or")
  echo "$line" | grep -q '||'      && candidates+=("or_and")
  echo "$line" | grep -q '>'       && candidates+=("gt_lt")
  echo "$line" | grep -q '<'       && candidates+=("lt_gt")
  echo "$line" | grep -q '"[^"]\{1,\}"' && candidates+=("empty_dquote")
  echo "$line" | grep -q "'[^']\{1,\}'" && candidates+=("empty_squote")
  echo "$line" | grep -qE 'stderr|>&2'  && candidates+=("drop_stderr")
  echo "$line" | grep -q 'return'  && candidates+=("return_early")
  echo "$line" | grep -q 'exit'    && candidates+=("swap_exit")
  echo "$line" | grep -qE '\+|\-'  && candidates+=("swap_arith")

  # Pick random applicable mutation
  local pick="${candidates[$(( RANDOM % ${#candidates[@]} ))]}"

  case $pick in
    delete)         result="" ;;
    true_false)     result=$(echo "$line" | sed 's/true/false/') ;;
    false_true)     result=$(echo "$line" | sed 's/false/true/') ;;
    strict_eq_neq)  result=$(echo "$line" | sed 's/===/!==/')  ;;
    strict_neq_eq)  result=$(echo "$line" | sed 's/!==/===/')  ;;
    eq_neq)         result=$(echo "$line" | sed 's/==/!=/')    ;;
    neq_eq)         result=$(echo "$line" | sed 's/!=/==/')    ;;
    assign_neq)     result=$(echo "$line" | sed 's/ = / != /') ;;
    and_or)         result=$(echo "$line" | sed 's/&&/||/')    ;;
    or_and)         result=$(echo "$line" | sed 's/||/\&\&/')  ;;
    gt_lt)          result=$(echo "$line" | sed 's/>/</') ;;
    lt_gt)          result=$(echo "$line" | sed 's/</>/')  ;;
    empty_dquote)   result=$(echo "$line" | sed 's/"[^"]\{1,\}"/""/') ;;
    empty_squote)   result=$(echo "$line" | sed "s/'[^']\{1,\}'/''/") ;;
    drop_stderr)    result=$(echo "$line" | sed 's/ >&2//;s/ 2>[^ ]*//') ;;
    return_early)   result=$(echo "$line" | sed 's/return .*/return/;s/return .*/return nil/') ;;
    swap_exit)      result=$(echo "$line" | sed 's/exit 0/exit 1/;s/exit 1/exit 0/') ;;
    swap_arith)     result=$(echo "$line" | sed 's/+/-/;s/- (/+ (/') ;;
  esac

  echo "$result"
}

is_code_line() {
  local line="$1"
  # Skip empty lines, comments, pure whitespace
  [[ -z "${line// /}" ]] && return 1
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  [[ "$line" =~ ^[[:space:]]*-- ]] && return 1
  [[ "$line" =~ ^[[:space:]]*/\* ]] && return 1
  [[ "$line" =~ ^[[:space:]]*// ]] && return 1
  [[ "$line" =~ ^[[:space:]]*\* ]] && return 1
  return 0
}

# --- State ---
SURVIVED=0
KILLED=0
SKIPPED=0
SURVIVORS=()

# --- Colors ---
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'
  BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''
fi

printf "${BOLD}Mutation testing: %d rounds${RESET}\n\n" "$ROUNDS"

for (( i=1; i<=ROUNDS; i++ )); do
  # Pick random file
  file="${FILES[$(( RANDOM % ${#FILES[@]} ))]}"
  total_lines=$(wc -l < "$file")

  # Pick random code line (try up to 20 times)
  line_num=0
  original_line=""
  for (( attempt=0; attempt<20; attempt++ )); do
    line_num=$(( RANDOM % total_lines + 1 ))
    original_line=$(sed -n "${line_num}p" "$file")
    is_code_line "$original_line" && break
    line_num=0
  done
  [[ $line_num -eq 0 ]] && { SKIPPED=$((SKIPPED + 1)); continue; }

  # Apply mutation
  mutated_line=$(mutate_line "$original_line")

  # Skip if mutation had no effect
  [[ "$mutated_line" = "$original_line" ]] && { SKIPPED=$((SKIPPED + 1)); continue; }

  # Apply mutation to file
  cp "$file" "${file}.mutate.bak"
  if [[ -z "$mutated_line" ]]; then
    # Line deletion
    awk -v n="$line_num" 'NR!=n{print}' "${file}.mutate.bak" > "$file"
  else
    # Line replacement
    awk -v n="$line_num" -v rep="$mutated_line" 'NR==n{print rep;next}{print}' "${file}.mutate.bak" > "$file"
  fi

  # Syntax check
  checker="${SYNTAX_CHECK[$file]}"
  if ! $checker "$file" >/dev/null 2>&1; then
    # Syntax error — restore and skip
    mv "${file}.mutate.bak" "$file"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Run tests
  printf "  [%d/%d] %s:%d ... " "$i" "$ROUNDS" "$file" "$line_num"
  if make test-quick >/dev/null 2>&1; then
    # Tests passed — mutant survived!
    SURVIVED=$((SURVIVED + 1))
    printf "${RED}SURVIVED${RESET}\n"
    SURVIVORS+=("$(printf "%s:%d\n  original: %s\n  mutated:  %s" "$file" "$line_num" "$original_line" "$mutated_line")")
  else
    KILLED=$((KILLED + 1))
    printf "${GREEN}killed${RESET}\n"
  fi

  # Restore original
  mv "${file}.mutate.bak" "$file"
done

# --- Summary ---
TESTED=$((SURVIVED + KILLED))
printf "\n${BOLD}Results:${RESET}\n"
printf "  Rounds:   %d\n" "$ROUNDS"
printf "  Tested:   %d (syntax-valid mutations)\n" "$TESTED"
printf "  Killed:   ${GREEN}%d${RESET}\n" "$KILLED"
printf "  Survived: ${RED}%d${RESET}\n" "$SURVIVED"
printf "  Skipped:  %d (no-op or syntax errors)\n" "$SKIPPED"

if [[ $TESTED -gt 0 ]]; then
  score=$(( KILLED * 100 / TESTED ))
  printf "  Score:    %d%% mutations killed\n" "$score"
fi

if [[ ${#SURVIVORS[@]} -gt 0 ]]; then
  printf "\n${BOLD}${RED}Surviving mutants (test gaps):${RESET}\n\n"
  for s in "${SURVIVORS[@]}"; do
    printf "%s\n\n" "$s"
  done
fi

exit "$SURVIVED"
