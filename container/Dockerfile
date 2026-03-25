FROM alpine:3.21

LABEL org.opencontainers.image.title="pandia"
LABEL org.opencontainers.image.description="Markdown to PDF/HTML with diagrams and LaTeX math"
LABEL org.opencontainers.image.source="https://github.com/yaccob/pandia"
LABEL org.opencontainers.image.version="1.7.0"
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
    poppler-utils \
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

# Mermaid CLI, Markmap CLI, and diagram renderer dependencies
RUN npm install -g @mermaid-js/mermaid-cli markmap-cli \
    nomnoml @softwaretechnik/dbml-renderer wavedrom && \
    printf '{\n  "executablePath": "/usr/bin/chromium-browser",\n  "args": ["--no-sandbox", "--disable-gpu"]\n}\n' \
      > /etc/mermaid-puppeteer-config.json

ENV PUPPETEER_CONFIG=/etc/mermaid-puppeteer-config.json
ENV MMDC_PUPPETEER_CONFIG=/etc/mermaid-puppeteer-config.json
ENV NODE_PATH=/usr/local/lib/node_modules

# D2 diagram tool (Go binary)
RUN ARCH=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/') && \
    wget -q -O /tmp/d2.tar.gz \
      "https://github.com/terrastruct/d2/releases/download/v0.7.1/d2-v0.7.1-linux-${ARCH}.tar.gz" && \
    tar -xzf /tmp/d2.tar.gz -C /tmp && \
    cp /tmp/d2-v0.7.1/bin/d2 /usr/local/bin/d2 && \
    chmod +x /usr/local/bin/d2 && \
    rm -rf /tmp/d2*

# Install the Lua filter
COPY server/diagram-filter.lua /usr/local/share/pandoc/filters/diagram-filter.lua

# Mermaid render server (placed inside mermaid-cli for correct import resolution)
COPY server/mermaid-server.mjs /usr/local/lib/node_modules/@mermaid-js/mermaid-cli/mermaid-server.mjs

# Markmap renderer and generic diagram renderer
COPY server/markmap-render.mjs /usr/local/share/pandia/markmap-render.mjs
COPY server/diagram-renderer.mjs /usr/local/lib/node_modules/diagram-renderer.mjs

# Pandia HTTP server and CLI
COPY server/pandia-server.mjs /usr/local/share/pandia/pandia-server.mjs
COPY cli/bin/pandia-serve /usr/local/bin/pandia-serve
COPY cli/bin/pandia /usr/local/bin/pandia

WORKDIR /data

COPY container/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/pandia-serve /usr/local/bin/pandia

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
