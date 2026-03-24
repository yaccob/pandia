# pandia server

HTTP rendering server for Markdown with diagrams and LaTeX math.

## API

Two endpoints. See [`openapi.yaml`](openapi.yaml) for the full OpenAPI 3.0 spec.

### `GET /health`

Returns `ok` (text/plain). Use for readiness probes.

### `POST /render`

Accepts raw Markdown as the request body, returns rendered HTML or PDF.

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `format` | `html`, `pdf` | `html` | Output format |
| `math` | `mathjax`, `mathml` | `mathml` | Math rendering engine |
| `maxwidth` | CSS value | `60em` | Max content width (HTML) |
| `center_math` | `true`, `false` | `false` | Center display math |
| `kroki_server` | URL | — | Kroki server for extra diagram types |

```bash
# Render to HTML
curl -X POST http://localhost:3300/render \
  --data-binary @myfile.md > output.html

# Render to PDF
curl -X POST "http://localhost:3300/render?format=pdf" \
  --data-binary @myfile.md > output.pdf

# With Kroki diagrams
curl -X POST "http://localhost:3300/render?kroki_server=https://kroki.io" \
  --data-binary @myfile.md > output.html
```

## Starting the Server

```bash
# Directly with Node.js (requires pandoc + tools installed)
node pandia-server.mjs

# Custom port via environment variable
PANDIA_PORT=8080 node pandia-server.mjs
```

## Architecture

```
POST /render (Markdown body)
    → pandia-server.mjs
    → pandoc --lua-filter=diagram-filter.lua
        → PlantUML, Graphviz, Mermaid, TikZ, ... (concurrent subprocesses)
        → diagram-renderer.mjs (Nomnoml, DBML, D2, WaveDrom)
        → markmap-render.mjs (Markmap)
        → Kroki HTTP (BPMN, ERD, Pikchr, ...)
    → HTML (self-contained, inline SVGs) or PDF
```

## Key Files

| File | Purpose |
|------|---------|
| `pandia-server.mjs` | HTTP server (POST /render, GET /health) |
| `diagram-filter.lua` | Pandoc Lua filter — diagram routing, rendering, batching |
| `diagram-renderer.mjs` | Node.js renderer for Nomnoml, DBML, D2, WaveDrom |
| `markmap-render.mjs` | Markmap HTML fragments and PDF generation |
| `mermaid-server.mjs` | Persistent Mermaid renderer (keeps Chromium alive) |
| `openapi.yaml` | OpenAPI 3.0 specification |

## Local Development

```bash
npm install                # Install diagram renderer dependencies
node pandia-server.mjs     # Start server (default port 3300)
```

Requires: Node.js, pandoc, and diagram tools (plantuml, graphviz, mermaid-cli, etc.).
