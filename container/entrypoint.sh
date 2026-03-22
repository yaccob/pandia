#!/bin/sh
set -e

# Docker entrypoint for pandia container
#
# Usage:
#   docker run ... yaccob/pandia pandia-serve [OPTIONS] [PORT]   → start server
#   docker run ... yaccob/pandia --serve [PORT]                  → start server (compat)
#   docker run ... yaccob/pandia [OPTIONS] <input.md>            → render file

FILTER="/usr/local/share/pandoc/filters/diagram-filter.lua"
PANDOC_COMMON="--lua-filter=$FILTER --from=gfm+tex_math_dollars"

# --- Serve mode ---
if [ "${1:-}" = "pandia-serve" ] || [ "${1:-}" = "--serve" ]; then
  shift
  exec /usr/local/bin/pandia-serve "$@"
fi

# --- Render mode ---
usage() {
  cat <<'EOF'
Usage: docker run --rm -v "$PWD:/data" yaccob/pandia [OPTIONS] <input.md>
       docker run -d -p 3300:3300 yaccob/pandia pandia-serve [PORT]

Render options:
  -t, --to FORMAT       Output format: pdf, html (default: html)
  -o, --output FILE     Write output to FILE (default: stdout)
  --maxwidth WIDTH      Max content width for HTML output (default: 60em)
  --center-math         Center block formulas (default: left-aligned)
  --kroki-server URL    Enable Kroki for additional diagram types
  -h, --help            Show this help

Server options (pandia-serve):
  --kroki-server URL    Kroki server for all requests
  PORT                  Port to listen on (default: 3300)

Diagram types: plantuml, graphviz/dot, mermaid, markmap, ditaa, tikz,
  nomnoml, dbml, d2, wavedrom, dir
With Kroki: + bpmn, erd, pikchr, svgbob, excalidraw, vega, ...
EOF
  exit 0
}

FORMAT=""
OUTPUT_FILE=""
MAXWIDTH="60em"
CENTER_MATH=false
KROKI_URL=""
INPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--to)
      if [ -n "$FORMAT" ]; then
        echo "Error: -t/--to can only be specified once." >&2
        exit 1
      fi
      case "$2" in
        pdf)  FORMAT=pdf ;;
        html) FORMAT=html ;;
        *)    echo "Error: Unknown format '$2'." >&2; exit 1 ;;
      esac
      shift 2 ;;
    -o|--output)    OUTPUT_FILE="$2"; shift 2 ;;
    --maxwidth)     MAXWIDTH="$2"; shift 2 ;;
    --center-math)  CENTER_MATH=true; shift ;;
    --kroki-server) KROKI_URL="$2"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo "Unknown option: $1" >&2; exit 1 ;;
    *)              INPUT="$1"; shift ;;
  esac
done

if [ -z "$INPUT" ]; then
  echo "Error: No input file specified." >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: File '$INPUT' not found." >&2
  exit 1
fi

if [ -z "$FORMAT" ]; then
  FORMAT=html
fi

if [ -n "$KROKI_URL" ]; then
  export PANDIA_KROKI_URL="$KROKI_URL"
fi

# Start mermaid render server if available
MERMAID_SERVER_SCRIPT="/usr/local/lib/node_modules/@mermaid-js/mermaid-cli/mermaid-server.mjs"
if [ -f "$MERMAID_SERVER_SCRIPT" ]; then
  node "$MERMAID_SERVER_SCRIPT" &
  for _ in $(seq 1 30); do
    [ -f /tmp/mermaid-server.ready ] && break
    sleep 0.2
  done
  if [ -f /tmp/mermaid-server.ready ]; then
    export MERMAID_SERVER="http://127.0.0.1:$(cat /tmp/mermaid-server.ready)"
  fi
fi

MATH_FLAGS=""
MATH_ENGINE="--mathml"
if [ "$FORMAT" = pdf ]; then
  MATH_ENGINE=""
  if [ "$CENTER_MATH" = false ]; then
    MATH_FLAGS="-V classoption=fleqn"
  fi
else
  if [ "$CENTER_MATH" = false ]; then
    MATH_FLAGS="-V header-includes=<style>math[display=block]{display:block!important;text-align:left!important}</style>"
  fi
fi

if [ -n "$OUTPUT_FILE" ]; then
  echo "Generating ${OUTPUT_FILE} ..." >&2
  if [ "$FORMAT" = pdf ]; then
    pandoc $PANDOC_COMMON \
      --to=pdf --pdf-engine=pdflatex \
      -V geometry:margin=2.5cm $MATH_FLAGS \
      --standalone \
      -o "$OUTPUT_FILE" "$INPUT"
  else
    pandoc $PANDOC_COMMON \
      --to=html5 --standalone --embed-resources $MATH_ENGINE \
      -V maxwidth="$MAXWIDTH" $MATH_FLAGS \
      -o "$OUTPUT_FILE" "$INPUT"
  fi
  echo "  -> $OUTPUT_FILE" >&2
else
  echo "Generating ${FORMAT} ..." >&2
  if [ "$FORMAT" = pdf ]; then
    pandoc $PANDOC_COMMON \
      --to=pdf --pdf-engine=pdflatex \
      -V geometry:margin=2.5cm $MATH_FLAGS \
      --standalone \
      "$INPUT"
  else
    pandoc $PANDOC_COMMON \
      --to=html5 --standalone --embed-resources $MATH_ENGINE \
      -V maxwidth="$MAXWIDTH" $MATH_FLAGS \
      "$INPUT"
  fi
fi
