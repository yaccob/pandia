FROM alpine:3.21

LABEL org.opencontainers.image.title="pandia"
LABEL org.opencontainers.image.description="Markdown to PDF/HTML with PlantUML, Graphviz, Mermaid, Ditaa and LaTeX math"
LABEL org.opencontainers.image.source="https://github.com/yaccob/pandia"
LABEL org.opencontainers.image.version="1.4.0"
LABEL org.opencontainers.image.licenses="MIT"

# Core tools: pandoc, texlive, graphviz, rsvg-convert
RUN apk add --no-cache \
    pandoc \
    texlive \
    texmf-dist-latexextra \
    texmf-dist-fontsrecommended \
    graphviz \
    librsvg \
    rsvg-convert \
    openjdk17-jre \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto \
    nodejs \
    npm \
    wget \
    curl

# PlantUML
RUN mkdir -p /opt/plantuml && \
    wget -q -O /opt/plantuml/plantuml.jar \
      "https://github.com/plantuml/plantuml/releases/latest/download/plantuml.jar" && \
    printf '#!/bin/sh\nexec java -jar /opt/plantuml/plantuml.jar "$@"\n' > /usr/local/bin/plantuml && \
    chmod +x /usr/local/bin/plantuml

# Mermaid CLI (with Chromium config for container use)
RUN npm install -g @mermaid-js/mermaid-cli && \
    printf '{\n  "executablePath": "/usr/bin/chromium-browser",\n  "args": ["--no-sandbox", "--disable-gpu"]\n}\n' \
      > /etc/mermaid-puppeteer-config.json

ENV PUPPETEER_CONFIG=/etc/mermaid-puppeteer-config.json
ENV MMDC_PUPPETEER_CONFIG=/etc/mermaid-puppeteer-config.json

# Install the Lua filter
COPY diagram-filter.lua /usr/local/share/pandoc/filters/diagram-filter.lua

# Mermaid render server (placed inside mermaid-cli for correct import resolution)
COPY mermaid-server.mjs /usr/local/lib/node_modules/@mermaid-js/mermaid-cli/mermaid-server.mjs

# Pandia HTTP server
COPY pandia-server.mjs /usr/local/share/pandia/pandia-server.mjs

WORKDIR /data

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
