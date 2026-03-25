# pandia CLI

Command-line tool for rendering Markdown with diagrams and LaTeX math.
Requires a running pandia server.

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
  --server URL          Server URL (default: http://localhost:3300)
  --maxwidth WIDTH      Max content width for HTML output (default: 60em)
  --center-math         Center block formulas (default: left-aligned)
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

### Specifying a Server

By default, pandia connects to `http://localhost:3300`. Use `--server` for a different URL:

```bash
pandia --server http://myserver:3300 myfile.md > output.html
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
```

## pandia-serve

Convenience wrapper to start a pandia server.

```
pandia-serve [PORT]

Options:
  -h, --help            Show this help

Environment:
  PANDIA_PORT           Alternative to PORT argument (default: 3300)
```

```bash
# Start server on default port 3300
pandia-serve

# Custom port
pandia-serve 8080

# Via Docker
docker run -d -p 3300:3300 yaccob/pandia pandia-serve
```
