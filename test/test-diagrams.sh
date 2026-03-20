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

# --- Ditaa ------------------------------------------------------------

section "ditaa: happy path"

test_ditaa_basic() {
  local input='```ditaa
+--------+   +-------+
|        |-->|       |
| cBLU   |   | cGRE  |
+--------+   +-------+
```'
  local out
  out=$(run_filter_isolated "$input")
  assert_contains "$out" "<img" "Ditaa generates image element"
  assert_contains "$out" "ditaa-" "Image uses ditaa prefix"
  assert_contains "$out" ".png" "Ditaa uses PNG format"
}
test_ditaa_basic

section "ditaa: error cases"

test_ditaa_empty() {
  local input='```ditaa
```'
  run_filter_isolated_both "$input"
  assert_contains "$LAST_STDOUT" "<img" "Ditaa empty block still produces image (PlantUML wrapper)"
}
test_ditaa_empty

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

test_pdf_ditaa() {
  local input='```ditaa
+---+
| A |
+---+
```'
  run_filter_pdf_keep "$input"
  local found
  found=$(ls "$WORK_DIR"/img/ditaa-*.png 2>/dev/null | head -1) || true
  assert_file_exists "${found:-/nonexistent}" "Ditaa produces PNG file for PDF output (always PNG)"
  teardown_workdir
}
test_pdf_ditaa

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

print_summary
exit $FAIL
