# Pandia Preview — VS Code Extension

Live preview for Markdown documents with embedded diagrams and LaTeX math.

## Features

- **Live preview** — updates automatically as you type (debounced)
- **All pandia diagram types** — PlantUML, Graphviz, Mermaid, Markmap, Nomnoml, DBML, D2, WaveDrom, TikZ, Ditaa, Directory Trees
- **Interactive Markmap** — mind maps are expandable/collapsible in the preview
- **LaTeX math** — rendered server-side as MathML (no JavaScript needed)
- **Theme-aware** — adapts to your VS Code color theme (light/dark)
- **Self-contained** — all images are inlined, no temp files

## Prerequisites

- **Docker** or **Podman** — the extension uses a pandia container for rendering

That's it. No local tool installation needed.

## Getting Started

1. Install the extension:
   ```bash
   # From the repo root:
   make vscode-install
   ```

2. Open a Markdown file

3. **Cmd+Shift+P** → **Pandia: Open Preview**

The extension automatically starts a pandia container if no server is running.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `pandia.serverUrl` | *(empty)* | URL of a running pandia server. If empty, a container is started automatically. |
| `pandia.containerImage` | `yaccob/pandia:latest` | Docker/Podman image to use. |
| `pandia.port` | `3300` | Port for the pandia server. |
| `pandia.krokiServer` | *(empty)* | Kroki server URL for additional diagram types (BPMN, ERD, Pikchr, etc.). Example: `https://kroki.io` |

### Using an existing server

If you already have a pandia server running (e.g. on a remote machine):

```json
{
  "pandia.serverUrl": "http://my-server:3300"
}
```

## How It Works

```
VS Code                          pandia container
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
