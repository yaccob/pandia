#!/usr/bin/env bash
# CLI integration test — verify example.md renders all diagram types
#
# Instead of hardcoding section names, this script finds all diagram
# sections in the HTML and verifies each one contains a rendered diagram
# (SVG, img, or markmap-container) rather than a raw code block (<pre>).
set -euo pipefail

HTML="${1:?Usage: $0 <example.html>}"
PASS=0
FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'

# Sections that should contain a rendered diagram
# (every h2/h3 that has a code block in example.md becomes a diagram section)
DIAGRAM_SECTIONS=(
  "Sequence Diagram"
  "Class Diagram"
  "EBNF Syntax"
  "Directed Graph"
  "State Machine"
  "Flowchart"
  "Gantt Chart"
  "Ditaa"
  "TikZ"
  "Nomnoml"
  "DBML"
  "WaveDrom"
)

# Sections that only render with specific tools (skip if not available)
# D2: only in container (Go binary)
if command -v d2 >/dev/null 2>&1; then
  DIAGRAM_SECTIONS+=("D2")
fi

# Kroki sections: only render when --kroki-server was used
KROKI_SECTIONS=(
  "BPMN"
  "Entity Relationship"
  "Pikchr"
  "Svgbob"
  "Nomnoml"     # also in native, but Kroki section has its own
  "WaveDrom"    # same
)

check_section() {
  local name="$1"
  local has_diagram
  has_diagram=$(sed -n "/$name/,/^<h[0-9]/p" "$HTML" | grep -c '<svg\|<img' || true)
  if [[ "$has_diagram" -gt 0 ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "$name"
    return
  fi
  # Check for markmap (inline HTML, not img/svg)
  local has_markmap
  has_markmap=$(sed -n "/$name/,/^<h[0-9]/p" "$HTML" | grep -c 'markmap-container' || true)
  if [[ "$has_markmap" -gt 0 ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "$name"
    return
  fi
  FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "$name"
}

# Check core diagram sections (always expected)
printf "${BOLD}Core diagram types:${RESET}\n"
for section in "${DIAGRAM_SECTIONS[@]}"; do
  check_section "$section"
done

# Check markmap separately (heading wraps across lines)
has_mm=$(grep -c 'markmap-container' "$HTML" || true)
if [[ "$has_mm" -gt 0 ]]; then
  PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   %s\n" "Markmap"
else
  FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "Markmap"
fi

# Check Kroki sections only if kroki was actually used (rendered diagrams present)
if grep -q 'img/kroki-' "$HTML" 2>/dev/null; then
  printf "\n${BOLD}Kroki-powered diagram types:${RESET}\n"
  for section in "${KROKI_SECTIONS[@]}"; do
    if grep -q "$section" "$HTML" 2>/dev/null; then
      check_section "$section"
    fi
  done
else
  printf "\n${BOLD}Kroki-powered diagram types:${RESET}\n"
  printf "  SKIP  No --kroki-server used\n"
fi

# Detect any code blocks that should have been rendered (catch-all)
printf "\n${BOLD}Unrendered code blocks (should be empty):${RESET}\n"
# Find <pre> blocks with diagram class names that should have been rendered
unrendered=$(grep -o '<pre class="[^"]*"' "$HTML" | grep -v 'sourceCode\|code-block' || true)
if [[ -z "$unrendered" ]]; then
  PASS=$((PASS + 1)); printf "  ${GREEN}OK${RESET}   No unrendered diagram blocks\n"
else
  # Some unrendered blocks might be expected (e.g., D2 without binary, Kroki without server)
  # Only fail if they're types we expect to be rendered
  while IFS= read -r line; do
    classname=$(echo "$line" | grep -o 'class="[^"]*"' | sed 's/class="//;s/"//')
    case "$classname" in
      d2)
        if command -v d2 >/dev/null 2>&1; then
          FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} Unrendered: %s\n" "$classname"
        else
          printf "  SKIP Unrendered %s (d2 not installed locally)\n" "$classname"
        fi
        ;;
      bpmn|erd|pikchr|svgbob|vega|vegalite|excalidraw|structurizr)
        # Kroki-only types — only a problem if kroki was actually used
        if grep -q 'img/kroki-' "$HTML" 2>/dev/null; then
          FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} Unrendered: %s (kroki configured but not rendered)\n" "$classname"
        else
          printf "  SKIP Unrendered %s (needs --kroki-server)\n" "$classname"
        fi
        ;;
      *)
        FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} Unrendered: %s\n" "$classname"
        ;;
    esac
  done <<< "$unrendered"
fi

printf "\nResults: "
if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}All $PASS checks passed${RESET}\n"
else
  printf "${RED}$FAIL failed${RESET}, $PASS passed\n"
  exit 1
fi
