# pandia

Markdown-to-PDF/HTML converter with built-in support for diagrams and LaTeX math.
Most diagrams render as **vector graphics** (PDF/SVG) for crisp output at any zoom level.

## Supported Features

**Built-in (pandia native)**

| Feature    | Code Block Syntax   | Output Format             |
|------------|---------------------|---------------------------|
| Dir Tree   | `` ```dir ``        | Vector (SVG)              |

**Pandoc native**

| Feature    | Syntax              | Output Format             |
|------------|---------------------|---------------------------|
| LaTeX Math | `$...$` / `$$...$$` | Native (Pandoc)           |

**Local tools** (no network required)

| Feature    | Code Block Syntax   | Output Format             |
|------------|---------------------|---------------------------|
| PlantUML   | `` ```plantuml ``   | Vector (PDF/SVG)          |
| Graphviz   | `` ```graphviz ``   | Vector (PDF/SVG)          |
| Mermaid    | `` ```mermaid ``    | Vector (PDF/SVG)          |
| Ditaa      | `` ```ditaa ``      | Raster (PNG)              |
| TikZ       | `` ```tikz ``       | Vector (PDF), PNG in HTML |

**Kroki-powered** (requires `--kroki` flag)

| Feature    | Code Block Syntax   | Output Format             |
|------------|---------------------|---------------------------|
| BPMN       | `` ```bpmn ``       | Vector (PDF/SVG)          |
| D2         | `` ```d2 ``         | Vector (PDF/SVG)          |
| DBML       | `` ```dbml ``       | Vector (PDF/SVG)          |
| ERD        | `` ```erd ``        | Vector (PDF/SVG)          |
| Svgbob     | `` ```svgbob ``     | Vector (PDF/SVG)          |
| WaveDrom   | `` ```wavedrom ``   | Vector (PDF/SVG)          |
| Nomnoml    | `` ```nomnoml ``    | Vector (PDF/SVG)          |
| Pikchr     | `` ```pikchr ``     | Vector (PDF/SVG)          |

## Installation

### macOS / Linux (Homebrew)

```bash
brew install yaccob/tap/pandia
```

This installs `pandia` and all required tools (Pandoc, PlantUML, Graphviz, Mermaid CLI, librsvg).

> **Note:** PDF output requires a LaTeX distribution. Install with `brew install --cask basictex`.

### Manual Install

```bash
curl -fsSL https://raw.githubusercontent.com/yaccob/pandia/v1.4.0/install.sh | sh
```

Installs the `pandia` script to `~/.local/bin`. You still need either:
- **Local tools:** `pandoc`, `plantuml`, `dot`, `mmdc`, `rsvg-convert`, `pdflatex`
- **Or just Docker/Podman** — pandia uses it as automatic fallback

### Docker Only

```bash
docker pull yaccob/pandia
docker run --rm -v "$PWD:/data" yaccob/pandia -t pdf -t html myfile.md
```

## Usage

```
pandia [OPTIONS] <input.md>

Options:
  -t, --to FORMAT    Output format: pdf, html (default: html; repeatable)
  --watch            Watch for changes and regenerate automatically
  -o, --output NAME  Base name for output files (default: derived from input)
  --maxwidth WIDTH   Max content width for HTML output (default: 60em)
  --docker           Force Docker mode (skip local tools)
  --local            Force local mode (fail if tools missing)
  -v, --version      Show version
  -h, --help         Show this help
```

### Examples

```bash
# Generate HTML (default)
pandia myfile.md

# Generate PDF
pandia -t pdf myfile.md

# Generate both PDF and HTML
pandia -t pdf -t html myfile.md

# Watch mode — regenerate on every save
pandia --watch -t pdf -t html myfile.md

# Custom output name
pandia -t pdf -o report myfile.md

# Force Docker even if local tools are available
pandia --docker -t pdf myfile.md
```

## Example Document

````markdown
---
title: "Demo"
---

## Sequence Diagram

```plantuml
@startuml
Alice -> Bob : Hello
Bob --> Alice : Hi
@enduml
```

## Flowchart

```mermaid
flowchart LR
    A[Start] --> B{OK?}
    B -- Yes --> C[Done]
    B -- No --> A
```

## State Machine

```graphviz
digraph { rankdir=LR; A -> B -> C; }
```

## Formula

$$E = mc^2$$

## Directory Tree

```dir
my-project
  src
    index.ts
    utils.ts
  tests/
  README.md
```
````

### Directory Tree Syntax

The `dir` block renders directory trees as SVG graphics. The syntax is plain
indented text — no special characters needed:

- **Indentation** defines the hierarchy (consistent spaces per level)
- **Trailing `/`** marks a directory (displayed in bold, slash stripped from output)
- Entries with children are automatically detected as directories
- The root entry (first line, no indentation) is always bold

## Why "pandia"?

The name is a blend of **Pan**doc and **dia**grams — the two things this tool
brings together. It also happens to echo the Greek *pan* (all) and *dia* (through),
which isn't a bad motto for a converter that pushes everything through one pipeline.
And if you want to get mythological: Pandia was a Greek goddess of the full moon,
daughter of Zeus and Selene — illuminating things that would otherwise stay in the dark.
Much like your diagrams before you ran `pandia --all`.

## How It Works

pandia wraps [Pandoc](https://pandoc.org/) with a custom Lua filter that intercepts
`plantuml`, `graphviz`, `mermaid`, `ditaa`, `tikz`, and `dir` code blocks, renders them via their
respective CLI tools (or `pdflatex` for TikZ), and passes the results back to Pandoc for PDF or HTML output.

- **Local mode:** Calls tools directly — fast, no overhead
- **Docker mode:** Runs everything in a self-contained container — no setup required

The CLI automatically detects which mode to use: local tools if available, Docker as fallback.

## License

MIT
