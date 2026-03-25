# Pandia Preview — VS Code Extension

Live preview for Markdown documents with embedded diagrams and LaTeX math.

## Features

- **Live preview** — updates automatically as you type (debounced)
- **All pandia diagram types** — PlantUML, Graphviz, Mermaid, Markmap, Nomnoml, DBML, D2, WaveDrom, TikZ, Directory Trees
- **Interactive Markmap** — mind maps are expandable/collapsible in the preview
- **LaTeX math** — rendered server-side as MathML (no JavaScript needed)
- **Theme-aware** — adapts to your VS Code color theme (light/dark)
- **Self-contained** — all images are inlined, no temp files

## Prerequisites

A running pandia server. Start one with Docker/Podman:

```bash
docker run -d -p 3300:3300 yaccob/pandia pandia-serve 3300
```

## Getting Started

1. Install the extension:
   ```bash
   # From the repo root:
   make vscode-install
   ```

2. Configure the server URL in VS Code settings:
   ```json
   {
     "pandia.serverUrl": "http://localhost:3300"
   }
   ```

3. Open a Markdown file

4. **Cmd+Shift+P** → **Pandia: Open Preview**

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `pandia.serverUrl` | *(empty)* | URL of a running pandia server (e.g. `http://localhost:3300`). |

## How It Works

```
VS Code                          pandia server
┌─────────────┐                 ┌──────────────────┐
│ Editor      │                 │ POST /render      │
│ (Markdown)  │── HTTP POST ──→│ pandoc + filter   │
│             │    raw text     │ → HTML + inline   │
│ Webview     │◄── HTML ───────│   SVGs + MathML   │
│ (Preview)   │                 │                   │
└─────────────┘                 └──────────────────┘
```

The extension sends the Markdown content to the pandia server's `POST /render`
endpoint with `math=mathml`. The server renders it with Pandoc and the diagram
filter, embedding all images as inline SVGs and math as MathML. The result is
displayed in a VS Code Webview panel.
