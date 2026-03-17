#!/bin/sh
set -e

FILTER="/usr/local/share/pandoc/filters/diagram-filter.lua"
PANDOC_COMMON="--lua-filter=$FILTER --from=gfm+tex_math_dollars"

usage() {
  cat <<'EOF'
Usage: docker run --rm -v "$PWD:/data" yaccob/pandia [OPTIONS] <input.md>

Options:
  --pdf              Generate PDF output (default if no format specified)
  --html             Generate HTML output
  --all              Generate both PDF and HTML
  -o, --output NAME  Base name for output files (default: derived from input)
  -h, --help         Show this help

Examples:
  docker run --rm -v "$PWD:/data" yaccob/pandia example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia --html example.md
  docker run --rm -v "$PWD:/data" yaccob/pandia --all -o report example.md
EOF
  exit 0
}

# Defaults
FORMAT_PDF=false
FORMAT_HTML=false
OUTPUT_BASE=""
INPUT=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --pdf)       FORMAT_PDF=true; shift ;;
    --html)      FORMAT_HTML=true; shift ;;
    --all)       FORMAT_PDF=true; FORMAT_HTML=true; shift ;;
    -o|--output) OUTPUT_BASE="$2"; shift 2 ;;
    -h|--help)   usage ;;
    -*)          echo "Unknown option: $1" >&2; usage ;;
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

# Default to PDF if no format specified
if [ "$FORMAT_PDF" = false ] && [ "$FORMAT_HTML" = false ]; then
  FORMAT_PDF=true
fi

# Derive output base name from input if not specified
if [ -z "$OUTPUT_BASE" ]; then
  OUTPUT_BASE="$(basename "$INPUT" .md)"
fi

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
    -o "${OUTPUT_BASE}.html" "$INPUT"
  echo "  -> ${OUTPUT_BASE}.html"
fi
