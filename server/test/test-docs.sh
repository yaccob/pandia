#!/usr/bin/env bash
# Mechanical documentation checks — verifies that docs match the actual code.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

README="$PROJECT_DIR/README.md"
CLI_README="$PROJECT_DIR/cli/README.md"
SERVER_README="$PROJECT_DIR/server/README.md"
VSCODE_README="$PROJECT_DIR/extension/README.md"
OPENAPI="$PROJECT_DIR/server/openapi.yaml"
PACKAGE_JSON="$PROJECT_DIR/extension/package.json"

# =====================================================================
# 1. CLI --help options must appear in README.md
# =====================================================================
section "docs: CLI options in README"

HELP_OUTPUT=$("$PANDIA" --help 2>&1)

# Extract long options from --help (e.g. --watch, --server, --output)
help_options=$(echo "$HELP_OUTPUT" | grep -oE -- '--[a-z][-a-z]*' | sort -u)

for opt in $help_options; do
  # Skip --help and --version — not interesting for docs
  case "$opt" in
    --help|--version) continue ;;
  esac
  cli_readme_content=$(cat "$CLI_README")
  if echo "$cli_readme_content" | grep -qF -- "$opt"; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} CLI README mentions %s\n" "$opt"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: CLI README missing CLI option: $opt"
    printf "  ${RED}FAIL${RESET} CLI README missing CLI option: %s\n" "$opt"
  fi
done

# Extract short options from --help (e.g. -t, -o, -v, -h)
help_short_options=$(echo "$HELP_OUTPUT" | grep -oE -- '-[a-z],' | sed 's/,$//' | sort -u)

for opt in $help_short_options; do
  case "$opt" in
    -h|-v) continue ;;
  esac
  if echo "$cli_readme_content" | grep -qF -- "$opt"; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} README mentions %s\n" "$opt"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: README missing CLI short option: $opt"
    printf "  ${RED}FAIL${RESET} README missing CLI short option: %s\n" "$opt"
  fi
done

# =====================================================================
# 2. README must not mention removed/non-existent CLI options
# =====================================================================
section "docs: no phantom CLI options in README"

# Options that were removed or never existed
# Check for removed standalone flags (word boundary match, not substrings)
check_no_phantom() {
  local opt="$1"
  # Match --flag as a standalone word (not inside pandia-serve etc.)
  if echo "$cli_readme_content" | grep -qE "(^|[[:space:]])${opt}([[:space:]]|$)"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: README mentions removed option: $opt"
    printf "  ${RED}FAIL${RESET} README mentions removed option: %s\n" "$opt"
  else
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} README does not mention removed option: %s\n" "$opt"
  fi
}
check_no_phantom "--serve"
check_no_phantom "--docker"
check_no_phantom "--local"

# -t must not be described as "repeatable"
if echo "$cli_readme_content" | grep -qi "repeatable"; then
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: README still describes -t as repeatable"
  printf "  ${RED}FAIL${RESET} README still describes -t as repeatable\n"
else
  PASS=$((PASS + 1))
  printf "  ${GREEN}PASS${RESET} README does not describe -t as repeatable\n"
fi

# =====================================================================
# 3. API endpoints in README must match openapi.yaml
# =====================================================================
section "docs: API endpoints match openapi.yaml"

if [[ -f "$OPENAPI" ]]; then
  # Extract paths from openapi.yaml
  api_paths=$(grep -E '^\s+/[a-z]' "$OPENAPI" | sed 's/[: ]//g' | sort -u)

  server_readme_content=$(cat "$SERVER_README")
  for path in $api_paths; do
    if echo "$server_readme_content" | grep -qF -- "$path"; then
      PASS=$((PASS + 1))
      printf "  ${GREEN}PASS${RESET} Server README documents API endpoint %s\n" "$path"
    else
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: Server README missing API endpoint: $path"
      printf "  ${RED}FAIL${RESET} Server README missing API endpoint: %s\n" "$path"
    fi
  done

  # Server README must not mention /preview (removed endpoint)
  if echo "$server_readme_content" | grep -qF '/preview'; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: README mentions removed /preview endpoint"
    printf "  ${RED}FAIL${RESET} README mentions removed /preview endpoint\n"
  else
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} README does not mention removed /preview endpoint\n"
  fi
else
  printf "  SKIP openapi.yaml not found\n"
fi

# =====================================================================
# 4. VS Code extension README: settings match package.json
# =====================================================================
section "docs: VS Code settings in README"

if [[ -f "$PACKAGE_JSON" && -f "$VSCODE_README" ]]; then
  vscode_readme_content=$(cat "$VSCODE_README")

  # Extract setting names from package.json properties section (pandia.serverUrl, etc.)
  # Use the configuration.properties keys, not command IDs
  pkg_settings=$(sed -n '/"properties"/,/^    }/p' "$PACKAGE_JSON" \
    | grep -oE '"pandia\.[a-zA-Z]+"' | tr -d '"' | sort -u)

  for setting in $pkg_settings; do
    if echo "$vscode_readme_content" | grep -qF -- "$setting"; then
      PASS=$((PASS + 1))
      printf "  ${GREEN}PASS${RESET} VS Code README documents %s\n" "$setting"
    else
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: VS Code README missing setting: $setting"
      printf "  ${RED}FAIL${RESET} VS Code README missing setting: %s\n" "$setting"
    fi
  done

  # VS Code README must not mention /preview (removed endpoint)
  if echo "$vscode_readme_content" | grep -qF '/preview'; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: VS Code README mentions removed /preview endpoint"
    printf "  ${RED}FAIL${RESET} VS Code README mentions removed /preview endpoint\n"
  else
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} VS Code README does not mention /preview endpoint\n"
  fi
else
  printf "  SKIP package.json or VS Code README not found\n"
fi

# =====================================================================
# 5. Version consistency
# =====================================================================
section "docs: version consistency"

cli_version=$("$PANDIA" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

if [[ -f "$OPENAPI" ]]; then
  api_version=$(grep -E '^\s+version:' "$OPENAPI" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ "$cli_version" = "$api_version" ]]; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} CLI version (%s) matches openapi.yaml (%s)\n" "$cli_version" "$api_version"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: CLI version ($cli_version) != openapi.yaml ($api_version)"
    printf "  ${RED}FAIL${RESET} CLI version (%s) != openapi.yaml (%s)\n" "$cli_version" "$api_version"
  fi
fi

# =====================================================================
# 6. Diagram types in README match --help
# =====================================================================
section "docs: diagram types in README"

# Core types listed in --help
help_types="plantuml graphviz mermaid markmap tikz nomnoml dbml d2 wavedrom dir"
for dtype in $help_types; do
  if grep -qiF "$dtype" "$README"; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} README mentions diagram type: %s\n" "$dtype"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: README missing diagram type: $dtype"
    printf "  ${RED}FAIL${RESET} README missing diagram type: %s\n" "$dtype"
  fi
done

print_summary
exit $FAIL
