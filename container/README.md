# pandia container

Docker/Podman image with all rendering tools pre-installed.

## Usage

### Render a File

```bash
docker run --rm -v "$PWD:/data" yaccob/pandia -t html -o output.html myfile.md
docker run --rm -v "$PWD:/data" yaccob/pandia -t pdf -o output.pdf myfile.md
```

### Start a Server

```bash
docker run -d -p 3300:3300 yaccob/pandia pandia-serve 3300
```

### Health Check

```bash
curl http://localhost:3300/health   # → "ok"
```

## What's Included

The image (Alpine-based) bundles:

- **Pandoc** + pandia Lua filter
- **PlantUML** (Java)
- **Graphviz** (dot)
- **Mermaid CLI** (Chromium-based)
- **Markmap CLI**
- **TikZ** (TeX Live, pdflatex, pdftocairo)
- **Nomnoml**, **DBML**, **WaveDrom** (Node.js)
- **D2** (Go binary)
- **librsvg** (rsvg-convert for SVG→PDF)

## Building

```bash
# From the project root:
make docker-build

# Or directly:
podman build -f container/Dockerfile -t yaccob/pandia .
```

The build context is the project root (not `container/`), because the Dockerfile
copies files from `server/` and `cli/`.
