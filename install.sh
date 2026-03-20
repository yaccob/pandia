#!/bin/sh
set -e

REPO="yaccob/pandia"
VERSION="1.4.0"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local}"

echo "Installing pandia v${VERSION} ..."

# Create directories
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/share/pandia"

# Download CLI script and filter
BASE_URL="https://raw.githubusercontent.com/${REPO}/v${VERSION}"
curl -fsSL "${BASE_URL}/bin/pandia" -o "$INSTALL_DIR/bin/pandia"
curl -fsSL "${BASE_URL}/diagram-filter.lua" -o "$INSTALL_DIR/share/pandia/diagram-filter.lua"
chmod +x "$INSTALL_DIR/bin/pandia"

echo ""
echo "Installed to:"
echo "  $INSTALL_DIR/bin/pandia"
echo "  $INSTALL_DIR/share/pandia/diagram-filter.lua"
echo ""

# Check PATH
case ":$PATH:" in
  *":$INSTALL_DIR/bin:"*) ;;
  *)
    echo "NOTE: Add $INSTALL_DIR/bin to your PATH:"
    echo "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
    echo ""
    ;;
esac

# Check dependencies
echo "Checking dependencies ..."
MISSING=""
for cmd in pandoc plantuml dot mmdc rsvg-convert; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  $cmd: OK"
  else
    echo "  $cmd: MISSING"
    MISSING="$MISSING $cmd"
  fi
done

if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
  echo "  docker/podman: OK (fallback available)"
else
  echo "  docker/podman: not found"
fi

if [ -n "$MISSING" ]; then
  echo ""
  echo "Some tools are missing:$MISSING"
  echo "pandia will use Docker as fallback if available."
  echo ""
  echo "To install all tools natively (macOS):"
  echo "  brew install pandoc plantuml graphviz mermaid-cli librsvg"
  echo "  brew install --cask basictex"
fi

echo ""
echo "Done. Run 'pandia --help' to get started."
