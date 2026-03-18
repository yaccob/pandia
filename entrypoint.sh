#!/bin/sh
set -e

FILTER="/usr/local/share/pandoc/filters/diagram-filter.lua"
PANDOC_COMMON="--lua-filter=$FILTER --from=gfm+tex_math_dollars"

usage() {
  cat <<'EOF'
Usage: docker run --rm -v "$PWD:/data" yaccob/pandia [OPTIONS] <input.md>

Options:
  -t, --to FORMAT    Output format: pdf, html (default: html; repeatable)
  --watch            Watch for changes and regenerate automatically
  -o, --output NAME  Base name for output files (default: derived from input)
  --maxwidth WIDTH   Max content width for HTML output (default: 60em)
  -h, --help         Show this help

Examples:
  docker run --rm -v "$PWD:/data" yaccob/pandia example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia -t pdf -t html example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia --watch -t pdf example.md
EOF
  exit 0
}

# Defaults
FORMAT_PDF=false
FORMAT_HTML=false
WATCH=false
OUTPUT_BASE=""
MAXWIDTH="60em"
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
    -o|--output)  OUTPUT_BASE="$2"; shift 2 ;;
    --maxwidth)   MAXWIDTH="$2"; shift 2 ;;
    -h|--help)    usage ;;
    -*)           echo "Unknown option: $1" >&2; usage ;;
    *)           INPUT="$1"; shift ;;
  esac
done

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

# Derive output base name from input if not specified
if [ -z "$OUTPUT_BASE" ]; then
  OUTPUT_BASE="$(basename "$INPUT" .md)"
fi

generate() {
  if [ "$FORMAT_PDF" = true ]; then
    echo "Generating ${OUTPUT_BASE}.pdf ..."
    pandoc $PANDOC_COMMON \
      --to=pdf \
      --pdf-engine=pdflatex \
      -V geometry:margin=2.5cm \
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
