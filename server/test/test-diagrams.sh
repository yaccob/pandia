#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

# --- PlantUML ---------------------------------------------------------

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

test_plantuml_without_startuml() {
  local input='```plantuml
actor User
participant "Backend" as BE
User -> BE : Request
BE --> User : Response
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "PlantUML without @startuml wrapper renders"
  assert_contains "$out" ".svg" "PlantUML without @startuml produces SVG"
}
test_plantuml_without_startuml

test_plantuml_ebnf() {
  local input='```plantuml
@startebnf
expr = term , { ("+" | "-") , term } ;
term = factor , { ("*" | "/") , factor } ;
factor = number | "(" , expr , ")" ;
@endebnf
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "PlantUML EBNF generates image"
}
test_plantuml_ebnf

section "plantuml: error cases"

test_plantuml_invalid_syntax() {
  local input='```plantuml
@startuml
this is not valid plantuml syntax %%%
@enduml
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "plantuml error" "PlantUML error shown in output on invalid syntax"
  assert_contains "$LAST_STDERR" "plantuml error" "PlantUML error on stderr"
}
test_plantuml_invalid_syntax

# --- Graphviz ---------------------------------------------------------

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

# --- Mermaid ----------------------------------------------------------

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

# --- TikZ -------------------------------------------------------------

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

# --- Unknown type -----------------------------------------------------

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

# --- PDF output -------------------------------------------------------

section "pdf output: diagram file types"

test_pdf_graphviz() {
  local input='```graphviz
digraph { A -> B; }
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/graphviz-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "Graphviz produces PDF file for PDF output"
  teardown_workdir
}
test_pdf_graphviz

test_pdf_plantuml() {
  local input='```plantuml
@startuml
Alice -> Bob: hello
@enduml
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/plantuml-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "PlantUML produces PDF file for PDF output"
  teardown_workdir
}
test_pdf_plantuml

test_pdf_mermaid() {
  local input='```mermaid
graph LR
  A --> B
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/mermaid-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "Mermaid produces PDF file for PDF output"
  teardown_workdir
}
test_pdf_mermaid

test_pdf_tikz() {
  local input='```tikz
\draw (0,0) -- (1,1);
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/tikz-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "TikZ produces PDF file for PDF output"
  teardown_workdir
}
test_pdf_tikz


# --- Captions ---------------------------------------------------------

section "diagram captions"

test_caption_graphviz() {
  setup_workdir
  cat > "$WORK_DIR/input.md" << 'MDEOF'
```{.graphviz caption="My Graph"}
digraph { A -> B; }
```
MDEOF
  local out
  out=$(cd "$WORK_DIR" && pandoc --lua-filter=diagram-filter.lua --from=markdown -t html input.md 2>/dev/null)
  assert_contains "$out" "My Graph" "Graphviz caption rendered (--from=markdown)"
  teardown_workdir
}
test_caption_graphviz

test_caption_plantuml() {
  setup_workdir
  cat > "$WORK_DIR/input.md" << 'MDEOF'
```{.plantuml caption="Sequence"}
@startuml
Alice -> Bob: hi
@enduml
```
MDEOF
  local out
  out=$(cd "$WORK_DIR" && pandoc --lua-filter=diagram-filter.lua --from=markdown -t html input.md 2>/dev/null)
  assert_contains "$out" "Sequence" "PlantUML caption rendered (--from=markdown)"
  teardown_workdir
}
test_caption_plantuml

# --- Batching / multiple diagrams -------------------------------------

section "multiple diagrams and batching"

test_multiple_plantuml() {
  local input='```plantuml
@startuml
Alice -> Bob: first
@enduml
```

Some text.

```plantuml
@startuml
Carol -> Dave: second
@enduml
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_count "$out" "<img" 2 "Two PlantUML diagrams both rendered"
}
test_multiple_plantuml

test_multiple_mermaid() {
  local input='```mermaid
graph LR
  A --> B
```

```mermaid
graph TD
  C --> D
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_count "$out" "<img" 2 "Two Mermaid diagrams both rendered"
}
test_multiple_mermaid

test_mixed_diagram_types() {
  local input='```graphviz
digraph { A -> B; }
```

```plantuml
@startuml
Alice -> Bob: hello
@enduml
```

```dir
root
  child
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_count "$out" "<img" 2 "Two image elements from graphviz + plantuml"
  assert_contains "$out" "<svg" "Dir block SVG also present"
}
test_mixed_diagram_types

# --- Markmap -----------------------------------------------------------

section "markmap: happy path (HTML)"

test_markmap_basic_html() {
  local input='```markmap
# Root
## Branch A
### Leaf 1
## Branch B
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "markmap" "Markmap output contains markmap reference"
  assert_contains "$out" "<svg" "Markmap output contains SVG element"
  assert_contains "$out" "<script" "Markmap output contains script tags"
  assert_not_contains "$out" "<img" "Markmap HTML is inline, not an image"
}
test_markmap_basic_html

test_markmap_deep_tree() {
  local input='```markmap
# Project
## Frontend
### React
#### Components
#### Hooks
### TypeScript
## Backend
### Node.js
### PostgreSQL
## DevOps
### Docker
### CI/CD
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "Frontend" "Deep markmap contains branch content"
  assert_contains "$out" "Components" "Deep markmap contains leaf content"
  assert_contains "$out" "<svg" "Deep markmap renders SVG"
}
test_markmap_deep_tree

test_markmap_multiple() {
  local input='```markmap
# First Map
## A
## B
```

Some text between.

```markmap
# Second Map
## X
## Y
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_count "$out" "<svg" 2 "Two markmap blocks produce two SVGs"
  assert_contains "$out" "First Map" "First markmap content present"
  assert_contains "$out" "Second Map" "Second markmap content present"
  assert_contains "$out" "markmap-1" "First markmap has unique ID"
  assert_contains "$out" "markmap-2" "Second markmap has unique ID"
}
test_markmap_multiple

test_markmap_scripts_deduplication() {
  local input='```markmap
# Map 1
## A
```

```markmap
# Map 2
## B
```'
  local out
  out=$(run_filter_isolated "$input")
  # d3 and markmap-view scripts should only be loaded once
  # Each block's script checks for existing script tags before loading
  assert_contains "$out" "existing = document.querySelector" "Script deduplication logic present"
}
test_markmap_scripts_deduplication

section "markmap: error cases"

test_markmap_empty_block() {
  local input='```markmap
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "markmap error" "Empty markmap shows error in output"
  assert_contains "$LAST_STDERR" "markmap error" "Empty markmap shows error on stderr"
}
test_markmap_empty_block

test_markmap_whitespace_only() {
  local input='```markmap


```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "markmap error" "Whitespace-only markmap shows error"
}
test_markmap_whitespace_only

section "markmap: temp file cleanup"

test_markmap_no_temp_files() {
  local input='```markmap
# Root
## A
## B
```'
  run_filter_isolated_keep "$input" >/dev/null
  # After rendering, temp files markmap-N.md and markmap-N.html in img/ should be cleaned up
  local leftover
  leftover=$(find "$WORK_DIR/img" -name 'markmap-*' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$leftover" -eq 0 ]]; then
    PASS=$((PASS + 1))
    printf "  ${GREEN}PASS${RESET} %s\n" "No markmap temp files left after rendering"
  else
    FAIL=$((FAIL + 1))
    printf "  ${RED}FAIL${RESET} %s\n" "No markmap temp files left after rendering"
    ERRORS="${ERRORS}\n  FAIL: Found $leftover markmap temp files in img/"
  fi
  teardown_workdir
}
test_markmap_no_temp_files

section "markmap: PDF output"

test_markmap_pdf() {
  # Markmap PDF requires puppeteer (via mermaid-cli) — skip if not available
  if ! node -e "require('puppeteer')" 2>/dev/null; then
    printf "  ${GREEN}SKIP${RESET} Markmap PDF: puppeteer not available (container-only)\n"
    return
  fi
  local input='```markmap
# Root
## Branch A
## Branch B
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/markmap-*.pdf 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "Markmap produces PDF for PDF output"

  # The PDF must contain the actual text — not just lines/circles
  if [[ -n "$found" && -f "$found" ]]; then
    local pdftext
    pdftext=$(pdftotext "$found" - 2>/dev/null) || true
    assert_contains "$pdftext" "Root" "Markmap PDF contains node text 'Root'"
    assert_contains "$pdftext" "Branch A" "Markmap PDF contains node text 'Branch A'"
  fi
  teardown_workdir
}
test_markmap_pdf

section "markmap: mixed with other diagrams"

test_markmap_with_graphviz() {
  local input='```markmap
# Overview
## Part A
## Part B
```

```graphviz
digraph { A -> B; }
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<svg" "Markmap SVG present"
  assert_contains "$out" "<img" "Graphviz image present"
  assert_contains "$out" "Overview" "Markmap content intact"
}
test_markmap_with_graphviz

# --- Stale cache: invalid code must not reuse previous output ---------

section "stale cache: invalid code must not reuse old output"

test_stale_plantuml() {
  setup_workdir
  # First render: valid plantuml → creates img/plantuml-1.svg
  local valid='```plantuml
@startuml
Alice -> Bob: hello
@enduml
```'
  (cd "$WORK_DIR" && echo "$valid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >/dev/null 2>/dev/null)

  # Second render: invalid plantuml in same workdir (img/ already exists with old SVG)
  local invalid='```plantuml
@startuml
this is %%% not valid
@enduml
```'
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && echo "$invalid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr") || true
  local out err
  out=$(cat "$tmpout")
  err=$(cat "$tmperr")

  assert_contains "$out" "plantuml error" "Stale plantuml: error shown (not old cached image)"
  assert_contains "$err" "plantuml error" "Stale plantuml: error on stderr"
  teardown_workdir
}
test_stale_plantuml

test_stale_graphviz() {
  setup_workdir
  # First render: valid graphviz → creates img/graphviz-1.svg
  local valid='```graphviz
digraph { A -> B; }
```'
  (cd "$WORK_DIR" && echo "$valid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >/dev/null 2>/dev/null)

  # Verify first render created the file
  local old_file
  old_file=$(ls "$WORK_DIR"/img/graphviz-*.svg 2>/dev/null | head -1) || true
  local old_size=""
  if [[ -n "$old_file" ]]; then
    old_size=$(wc -c < "$old_file" | tr -d ' ')
  fi

  # Second render: invalid graphviz in same workdir
  local invalid='```graphviz
this is not valid dot syntax
```'
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && echo "$invalid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr") || true
  local out err
  out=$(cat "$tmpout")
  err=$(cat "$tmperr")

  # The old graphviz-1.svg may still exist from the first render.
  # The filter must NOT silently serve the stale file as success.
  # It should either: show an error, or overwrite with a failed result.
  # Current bug: filter sees old file exists and treats it as success.
  assert_contains "$out" "graphviz error" "Stale graphviz: error shown (not old cached image)"
  assert_contains "$err" "graphviz error" "Stale graphviz: error on stderr"
  teardown_workdir
}
test_stale_graphviz

test_stale_mermaid() {
  setup_workdir
  # First render: valid mermaid
  local valid='```mermaid
graph LR
  A --> B
```'
  (cd "$WORK_DIR" && echo "$valid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >/dev/null 2>/dev/null)

  # Second render: invalid mermaid in same workdir
  local invalid='```mermaid
this is not a valid mermaid diagram @@@
```'
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && echo "$invalid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr") || true
  local out err
  out=$(cat "$tmpout")
  err=$(cat "$tmperr")

  assert_contains "$out" "mermaid error" "Stale mermaid: error shown (not old cached image)"
  assert_contains "$err" "mermaid error" "Stale mermaid: error on stderr"
  teardown_workdir
}
test_stale_mermaid

test_stale_tikz() {
  setup_workdir
  # First render: valid tikz
  local valid='```tikz
\draw (0,0) -- (1,1);
```'
  (cd "$WORK_DIR" && echo "$valid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >/dev/null 2>/dev/null)

  # Second render: invalid tikz in same workdir
  local invalid='```tikz
\this_is_not_valid_latex
```'
  local tmpout="$WORK_DIR/_stdout"
  local tmperr="$WORK_DIR/_stderr"
  (cd "$WORK_DIR" && echo "$invalid" | pandoc --lua-filter=diagram-filter.lua --from=gfm -t html >"$tmpout" 2>"$tmperr") || true
  local out err
  out=$(cat "$tmpout")
  err=$(cat "$tmperr")

  assert_contains "$out" "tikz error" "Stale tikz: error shown (not old cached image)"
  assert_contains "$err" "tikz error" "Stale tikz: error on stderr"
  teardown_workdir
}
test_stale_tikz

# --- SVG quality: preserveAspectRatio ---

section "svg quality: PlantUML scaling"

test_plantuml_no_preserveaspectratio_none() {
  local input='```plantuml
Alice -> Bob: Hello
Bob -> Alice: Hi
```'
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html5 2>"$tmpdir/err" > "$tmpdir/out" || true
  local out
  out=$(cat "$tmpdir/out")
  local err
  err=$(cat "$tmpdir/err")
  rm -rf "$tmpdir"

  # Filter must not crash (nil svgfile)
  assert_not_contains "$err" "attempt to concatenate a nil" \
    "PlantUML HTML render must not crash on nil svgfile"

  # sed must work on both macOS (BSD) and Linux (GNU)
  assert_not_contains "$err" "command i expects" \
    "sed must work on macOS (BSD sed)"
  assert_not_contains "$err" "rendering failed" \
    "PlantUML rendering must not fail"
  assert_contains "$out" "<img" \
    "PlantUML produces image output"

  # SVG must not have preserveAspectRatio="none" (breaks proportional scaling)
  assert_not_contains "$out" 'preserveAspectRatio="none"' \
    "PlantUML SVG must not have preserveAspectRatio=none"
}
test_plantuml_no_preserveaspectratio_none

# --- Markmap container height ---

section "markmap: HTML container height"

test_markmap_auto_fit() {
  local input='```markmap
# Software Architecture
## Frontend
### Framework
#### Vue.js
## Backend
### Languages
#### Python
```'
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html5 2>/dev/null > "$tmpdir/out" || true
  local out
  out=$(cat "$tmpdir/out")
  rm -rf "$tmpdir"
  # Must contain Markmap.create call (markmap-view's own rendering)
  assert_contains "$out" "Markmap.create" \
    "Markmap HTML includes Markmap.create call"
  # Must NOT contain fitContainer (server handles sizing, no client-side adjustment)
  if echo "$out" | grep -q "fitContainer"; then
    fail "Markmap HTML must not contain fitContainer (server-side sizing only)"
  else
    pass "Markmap HTML has no fitContainer (server-side sizing only)"
  fi
}
test_markmap_auto_fit

# --- TikZ SVG output ---

section "tikz: vector output in HTML"

test_tikz_html_is_svg() {
  # Only run if pdflatex and dvisvgm are available
  if ! command -v pdflatex >/dev/null 2>&1; then
    printf "  ${GREEN}SKIP${RESET} tikz SVG test: pdflatex not installed\n"
    return
  fi
  if ! command -v dvisvgm >/dev/null 2>&1; then
    printf "  ${GREEN}SKIP${RESET} tikz SVG test: dvisvgm not installed\n"
    return
  fi
  local input='```tikz
\begin{tikzpicture}
\draw (0,0) -- (1,1) -- (2,0) -- cycle;
\end{tikzpicture}
```'
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "$input" | pandoc --lua-filter="$FILTER" --from=gfm -t html5 2>/dev/null > "$tmpdir/out" || true
  local out
  out=$(cat "$tmpdir/out")
  rm -rf "$tmpdir"

  # TikZ must produce SVG (vector), not PNG (raster) in HTML output
  assert_contains "$out" ".svg" \
    "TikZ HTML output uses SVG (vector graphics)"
  assert_not_contains "$out" ".png" \
    "TikZ HTML output must not use PNG (raster)"
}
test_tikz_html_is_svg

# --- Integration test: example.md ---

section "integration: example.md renders all diagram types"

test_example_md_all_diagrams() {
  if [[ ! -f "$PROJECT_DIR/example.md" ]]; then
    printf "  ${GREEN}SKIP${RESET} example.md not found\n"
    return
  fi
  local tmpdir
  tmpdir=$(mktemp -d)
  cp "$PROJECT_DIR/example.md" "$tmpdir/"
  local out err
  out=$(cd "$tmpdir" && pandoc --lua-filter="$FILTER" --from=gfm+tex_math_dollars --to=html5 --standalone example.md 2>"$tmpdir/err") || true
  err=$(cat "$tmpdir/err")
  echo "$out" > "$tmpdir/example.html"

  # Every diagram type that is locally available must render (img, svg, or markmap-container)
  # PlantUML: Sequence, Class, EBNF
  for name in "Sequence Diagram" "Class Diagram" "EBNF Syntax"; do
    local has_img
    has_img=$(echo "$out" | sed -n "/$name/,/^<h[0-9]/p" | grep -c '<svg\|<img' || true)
    if [[ "$has_img" -gt 0 ]]; then
      PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: $name rendered"
    else
      FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: $name NOT rendered"
      ERRORS="${ERRORS}\n  FAIL: example.md $name not rendered"
    fi
  done

  # Graphviz
  for name in "Directed Graph" "State Machine"; do
    local has_img
    has_img=$(echo "$out" | sed -n "/$name/,/^<h[0-9]/p" | grep -c '<svg\|<img' || true)
    if [[ "$has_img" -gt 0 ]]; then
      PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: $name rendered"
    else
      FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: $name NOT rendered"
      ERRORS="${ERRORS}\n  FAIL: example.md $name not rendered"
    fi
  done

  # Mermaid
  for name in "Flowchart" "Gantt Chart"; do
    local has_img
    has_img=$(echo "$out" | sed -n "/$name/,/^<h[0-9]/p" | grep -c '<svg\|<img' || true)
    if [[ "$has_img" -gt 0 ]]; then
      PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: $name rendered"
    else
      FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: $name NOT rendered"
      ERRORS="${ERRORS}\n  FAIL: example.md $name not rendered"
    fi
  done

  # Markmap (uses markmap-container div, not img/svg)
  local has_markmap
  has_markmap=$(echo "$out" | grep -c 'markmap-container' || true)
  if [[ "$has_markmap" -gt 0 ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: Markmap rendered"
  else
    FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: Markmap NOT rendered"
    ERRORS="${ERRORS}\n  FAIL: example.md Markmap not rendered"
  fi

  # TikZ
  local has_tikz
  has_tikz=$(echo "$out" | sed -n "/TikZ/,/^<h[0-9]/p" | grep -c '<svg\|<img' || true)
  if [[ "$has_tikz" -gt 0 ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: TikZ rendered"
  else
    FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: TikZ NOT rendered"
    ERRORS="${ERRORS}\n  FAIL: example.md TikZ not rendered"
  fi

  # Node-renderer types (nomnoml, DBML, WaveDrom — D2 may not be installed locally)
  for name in "Nomnoml" "DBML" "WaveDrom"; do
    local has_img
    has_img=$(echo "$out" | sed -n "/$name/,/^<h[0-9]/p" | grep -c '<svg\|<img' || true)
    if [[ "$has_img" -gt 0 ]]; then
      PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: $name rendered"
    else
      FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: $name NOT rendered"
      ERRORS="${ERRORS}\n  FAIL: example.md $name not rendered"
    fi
  done

  # No rendering errors (ignore d2 if not installed)
  local real_errors
  real_errors=$(echo "$err" | grep 'pandia.*error' | grep -v 'd2' || true)
  if [[ -z "$real_errors" ]]; then
    PASS=$((PASS + 1)); printf "  ${GREEN}PASS${RESET} %s\n" "example.md: no rendering errors"
  else
    FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${RESET} %s\n" "example.md: rendering errors found"
    ERRORS="${ERRORS}\n  FAIL: $real_errors"
  fi

  rm -rf "$tmpdir"
}
test_example_md_all_diagrams

print_summary
exit $FAIL
