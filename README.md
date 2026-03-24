# pandia

Markdown to PDF/HTML with built-in support for diagrams and LaTeX math.
Most diagrams render as **vector graphics** (PDF/SVG) for crisp output at any zoom level.

## Supported Diagram Types

| Type | Syntax | Rendering | Availability |
|------|--------|-----------|--------------|
| PlantUML | `` ```plantuml `` | Vector (PDF/SVG) | Local + Container |
| Graphviz | `` ```graphviz `` | Vector (PDF/SVG) | Local + Container |
| Mermaid | `` ```mermaid `` | Vector (PDF/SVG) | Local + Container |
| Markmap | `` ```markmap `` | Interactive HTML / Vector PDF | Local + Container |
| Ditaa | `` ```ditaa `` | Raster (PNG) | Local + Container |
| TikZ | `` ```tikz `` | Vector (PDF/SVG) | Local + Container |
| Nomnoml | `` ```nomnoml `` | Vector (PDF/SVG) | Local + Container |
| DBML | `` ```dbml `` | Vector (PDF/SVG) | Local + Container |
| D2 | `` ```d2 `` | Vector (PDF/SVG) | Local + Container |
| WaveDrom | `` ```wavedrom `` | Vector (PDF/SVG) | Local + Container |
| Dir Tree | `` ```dir `` | Vector (SVG) | Local + Container |
| BPMN | `` ```bpmn `` | Vector (PDF/SVG) | Via Kroki |
| ERD | `` ```erd `` | Vector (PDF/SVG) | Via Kroki |
| Pikchr | `` ```pikchr `` | Vector (PDF/SVG) | Via Kroki |
| Svgbob | `` ```svgbob `` | Vector (PDF/SVG) | Via Kroki |

LaTeX math (`$...$` inline, `$$...$$` block) is supported natively via Pandoc.

## Components

| Component | Directory | Description |
|-----------|-----------|-------------|
| **CLI** | [`cli/`](cli/) | Command-line tool — renders via a pandia server |
| **Server** | [`server/`](server/) | HTTP rendering server (Pandoc + Lua filter + diagram tools) |
| **Container** | [`container/`](container/) | Docker/Podman image with all tools pre-installed |
| **VS Code Extension** | [`extension/`](extension/) | Live preview panel with all diagram types |

## Quick Start

**Docker (easiest):**

```bash
# Render a file
docker run --rm -v "$PWD:/data" yaccob/pandia -t html -o output.html myfile.md

# Start a server
docker run -d -p 3300:3300 yaccob/pandia pandia-serve 3300

# Use the server
pandia --server http://localhost:3300 myfile.md > output.html
```

**Homebrew (macOS/Linux):**

```bash
brew install yaccob/tap/pandia
pandia myfile.md > output.html
```

See the component READMEs for detailed usage.

## How It Works

pandia wraps [Pandoc](https://pandoc.org/) with a custom Lua filter that intercepts
diagram code blocks, renders them via their respective tools, and passes the results
back to Pandoc for PDF or HTML output.

```
input.md → pandoc + diagram-filter.lua → HTML or PDF
                    ↓
           PlantUML, Graphviz, Mermaid, TikZ, ...
           (as subprocesses, concurrent)
```

## Why "pandia"?

The name blends **Pan**doc and **dia**grams. It also echoes the Greek *pan* (all)
and *dia* (through). And if you want to get mythological: Pandia was a Greek goddess
of the full moon — illuminating things that would otherwise stay in the dark.

## License

MIT
