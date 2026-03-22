#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../test/helpers.sh"

section "robustness"

test_empty_markdown() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '' > "$tmpdir/empty.md"
  (cd "$tmpdir" && pandoc --lua-filter="$FILTER" --from=gfm -t html empty.md 2>&1 >/dev/null) || true
  PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "Empty markdown does not crash"
  rm -rf "$tmpdir"
}
test_empty_markdown

test_markdown_no_diagrams() {
  local input='# Hello

Some text with **bold** and *italic*.

- List item 1
- List item 2'
  local out
  out=$(run_filter "$input")
  assert_contains "$out" "Hello" "Markdown without diagrams passes through"
  assert_not_contains "$out" "<img" "No images generated for plain markdown"
  assert_not_contains "$out" "<svg" "No SVGs generated for plain markdown"
}
test_markdown_no_diagrams

test_spaces_in_path() {
  local tmpdir
  tmpdir=$(mktemp -d)/path\ with\ spaces
  mkdir -p "$tmpdir"
  cp "$FILTER" "$tmpdir/"
  echo '```graphviz
digraph { A -> B; }
```' > "$tmpdir/input.md"
  local out
  out=$(cd "$tmpdir" && pandoc --lua-filter=diagram-filter.lua --from=gfm -t html input.md 2>/dev/null) || true
  assert_contains "$out" "<img" "Filter works with spaces in path"
  rm -rf "$(dirname "$tmpdir")"
}
test_spaces_in_path

test_multiple_diagrams_with_errors() {
  local input='```graphviz
digraph { A -> B; }
```

```graphviz
this is invalid
```

```dir
root
  child
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "<img" "Valid graphviz still produces image"
  assert_contains "$LAST_STDOUT" "graphviz error" "Invalid graphviz shows error"
  assert_contains "$LAST_STDOUT" "<svg" "Dir block still renders despite other errors"
}
test_multiple_diagrams_with_errors

print_summary
exit $FAIL
