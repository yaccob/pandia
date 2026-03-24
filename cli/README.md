# pandia CLI

Command-line tool for rendering Markdown with diagrams and LaTeX math.

## Installation

### Homebrew (macOS/Linux)

```bash
brew install yaccob/tap/pandia
```

### Docker

No CLI installation needed — use the container directly:

```bash
docker run --rm -v "$PWD:/data" yaccob/pandia -t html -o output.html myfile.md
```

## Usage

```
pandia [OPTIONS] <input.md>

Options:
  -t, --to FORMAT       Output format: pdf, html (default: html)
  -o, --output FILE     Write output to FILE (default: stdout)
  --watch               Watch for changes and regenerate (requires -o)
  --server URL          Use a pandia server instead of local tools
  --maxwidth WIDTH      Max content width for HTML output (default: 60em)
  --center-math         Center block formulas (default: left-aligned)
  --kroki-server URL    Enable Kroki for additional diagram types (local mode only)
  -v, --version         Show version
  -h, --help            Show this help
```

### Output Modes

Without `-o`, pandia writes to **stdout** — ideal for piping:

```bash
pandia myfile.md > output.html
pandia -t pdf myfile.md > output.pdf
pandia myfile.md | less
```

With `-o FILE`, pandia writes to a file and shows progress on stderr:

```bash
pandia -o report.html myfile.md
pandia -t pdf -o report.pdf myfile.md
```

### Server Mode

```bash
# Render via server
pandia --server http://localhost:3300 myfile.md > output.html
pandia --server http://localhost:3300 -t pdf -o output.pdf myfile.md
```

## pandia-serve

Convenience wrapper to start a pandia server.

```
pandia-serve [OPTIONS] [PORT]

Options:
  --kroki-server URL    Kroki server URL for additional diagram types
  -h, --help            Show this help

Environment:
  PANDIA_KROKI_URL      Alternative to --kroki-server
  PANDIA_PORT           Alternative to PORT argument (default: 3300)
```

```bash
# Start server on default port 3300
pandia-serve

# Custom port
pandia-serve 8080

# With Kroki for additional diagram types
pandia-serve --kroki-server https://kroki.io

# Via Docker
docker run -d -p 3300:3300 yaccob/pandia pandia-serve
docker run -d -p 3300:3300 yaccob/pandia pandia-serve --kroki-server https://kroki.io
```

### Watch Mode

```bash
pandia --watch -o report.html myfile.md
```

Regenerates automatically whenever the input file changes. Requires `-o`.

### Examples

```bash
# HTML to stdout (default)
pandia myfile.md > output.html

# PDF to file
pandia -t pdf -o report.pdf myfile.md

# Custom max width
pandia --maxwidth 40em myfile.md > output.html

# Center block formulas
pandia --center-math -t pdf -o report.pdf myfile.md

# Enable Kroki diagram types
pandia --kroki-server https://kroki.io myfile.md > output.html
```
