#!/bin/sh
set -e

FILTER="/usr/local/share/pandoc/filters/diagram-filter.lua"
PANDOC_COMMON="--lua-filter=$FILTER --from=gfm+tex_math_dollars"

usage() {
  cat <<'EOF'
Usage: docker run --rm -v "$PWD:/data" yaccob/pandia [OPTIONS] <input.md>

Options:
  -t, --to FORMAT       Output format: pdf, html (default: html; repeatable)
  --watch               Watch for changes and regenerate automatically
  --serve [PORT]        Start HTTP server for rendering (default port: 3300)
  -o, --output NAME     Base name for output files (default: derived from input)
  --maxwidth WIDTH      Max content width for HTML output (default: 60em)
  --center-math         Center block formulas (default: left-aligned)
  --kroki               Enable Kroki for additional diagram types (uses \$PANDIA_KROKI_URL)
  --kroki-server URL    Enable Kroki with explicit server URL
  -h, --help            Show this help

Examples:
  docker run --rm -v "$PWD:/data" yaccob/pandia example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia -t pdf -t html example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia --watch -t pdf example.md
  docker run -d -p 3300:3300 -v "$PWD:/data" --name pandia yaccob/pandia --serve

Supported diagram types: plantuml, graphviz/dot, mermaid, ditaa, tikz, dir
With Kroki: + bpmn, d2, dbml, erd, excalidraw, nomnoml, svgbob, vega, wavedrom, ...
LaTeX math: \$...\$ (inline) and \$\$...\$\$ (block)
EOF
  exit 0
}

# Defaults
FORMAT_PDF=false
FORMAT_HTML=false
WATCH=false
SERVE=false
SERVE_PORT="3300"
OUTPUT_BASE=""
MAXWIDTH="60em"
CENTER_MATH=false
KROKI_URL=""
INPUT=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--to)
      case "$2" in
        pdf)  FORMAT_PDF=true ;;
        html) FORMAT_HTML=true ;;
        *)    echo "Error: Unknown format '$2'. Use 'pdf' or 'html'." >&2; exit 1 ;;
      esac
      shift 2 ;;
    --watch)      WATCH=true; shift ;;
    --serve)      SERVE=true
                  if [ -n "$2" ] && [ "${2#-}" = "$2" ] 2>/dev/null; then
                    SERVE_PORT="$2"; shift
                  fi
                  shift ;;
    -o|--output)  OUTPUT_BASE="$2"; shift 2 ;;
    --maxwidth)   MAXWIDTH="$2"; shift 2 ;;
    --center-math) CENTER_MATH=true; shift ;;
    --kroki)      KROKI_URL="${PANDIA_KROKI_URL:-}"; shift
                  if [ -z "$KROKI_URL" ]; then
                    echo "Error: --kroki requires PANDIA_KROKI_URL to be set." >&2
                    exit 1
                  fi ;;
    --kroki-server) KROKI_URL="$2"; shift 2 ;;
    -h|--help)    usage ;;
    -*)           echo "Unknown option: $1" >&2; usage ;;
    *)           INPUT="$1"; shift ;;
  esac
done

# Export Kroki URL for Lua filter
if [ -n "$KROKI_URL" ]; then
  export PANDIA_KROKI_URL="$KROKI_URL"
fi

# Handle --serve mode (no input file needed)
if [ "$SERVE" = true ]; then
  export PANDIA_PORT="$SERVE_PORT"
  echo "Starting pandia server on port $SERVE_PORT ..."
  exec node /usr/local/share/pandia/pandia-server.mjs
fi

if [ -z "$INPUT" ]; then
  echo "Error: No input file specified." >&2
  usage
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: File '$INPUT' not found." >&2
  exit 1
fi

# Default to HTML if no format specified
if [ "$FORMAT_PDF" = false ] && [ "$FORMAT_HTML" = false ]; then
  FORMAT_HTML=true
fi

# Start mermaid render server (keeps Chromium alive across rebuilds)
MERMAID_SERVER_SCRIPT="/usr/local/lib/node_modules/@mermaid-js/mermaid-cli/mermaid-server.mjs"
if [ -f "$MERMAID_SERVER_SCRIPT" ]; then
  node "$MERMAID_SERVER_SCRIPT" &
  MERMAID_PID=$!
  # Wait for server to be ready
  for _ in $(seq 1 30); do
    if [ -f /tmp/mermaid-server.ready ]; then break; fi
    sleep 0.2
  done
  if [ -f /tmp/mermaid-server.ready ]; then
    export MERMAID_SERVER="http://127.0.0.1:$(cat /tmp/mermaid-server.ready)"
  fi
fi

# Derive output base name from input if not specified
if [ -z "$OUTPUT_BASE" ]; then
  OUTPUT_BASE="$(basename "$INPUT" .md)"
fi

generate() {
  # Math alignment: left-aligned by default, centered with --center-math
  MATH_PDF_FLAGS=""
  MATH_HTML_FLAGS=""
  if [ "$CENTER_MATH" = false ]; then
    MATH_PDF_FLAGS="-V classoption=fleqn"
    MATH_HTML_FLAGS="-V header-includes=<script>window.MathJax={chtml:{displayAlign:'left'}};</script>"
  fi

  if [ "$FORMAT_PDF" = true ]; then
    echo "Generating ${OUTPUT_BASE}.pdf ..."
    pandoc $PANDOC_COMMON \
      --to=pdf \
      --pdf-engine=pdflatex \
      -V geometry:margin=2.5cm \
      $MATH_PDF_FLAGS \
      --standalone \
      -o "${OUTPUT_BASE}.pdf" "$INPUT"
    echo "  -> ${OUTPUT_BASE}.pdf"
  fi

  if [ "$FORMAT_HTML" = true ]; then
    echo "Generating ${OUTPUT_BASE}.html ..."
    pandoc $PANDOC_COMMON \
      --to=html5 \
      --standalone \
      --mathjax \
      -V maxwidth="$MAXWIDTH" \
      $MATH_HTML_FLAGS \
      -o "${OUTPUT_BASE}.html" "$INPUT"
    echo "  -> ${OUTPUT_BASE}.html"
  fi
}

if [ "$WATCH" = true ]; then
  echo "Watching '$INPUT' for changes (Ctrl+C to stop) ..."
  generate
  LAST_HASH=""
  while true; do
    HASH="$(md5sum "$INPUT" 2>/dev/null || stat -c%Y "$INPUT" 2>/dev/null)"
    if [ "$HASH" != "$LAST_HASH" ] && [ -n "$LAST_HASH" ]; then
      echo ""
      echo "--- Change detected at $(date +%H:%M:%S) ---"
      generate
    fi
    LAST_HASH="$HASH"
    sleep 1
  done
else
  generate
fi
