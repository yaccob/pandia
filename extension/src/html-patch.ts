/**
 * Post-process pandoc HTML for display in VS Code's Webview.
 *
 * Exported separately so it can be unit-tested without the vscode module.
 */

export function patchHtmlForWebview(html: string): string {
  const themeCss = `<style>
    html {
      color: var(--vscode-editor-foreground, #1a1a1a) !important;
      background-color: var(--vscode-editor-background, #fdfdfd) !important;
    }
    a { color: var(--vscode-textLink-foreground, #0066cc) !important; }
    code {
      color: var(--vscode-textPreformat-foreground, inherit) !important;
      background-color: var(--vscode-textPreformat-background, rgba(128,128,128,0.15)) !important;
    }
    pre {
      background-color: var(--vscode-textCodeBlock-background, rgba(128,128,128,0.1)) !important;
      padding: 12px !important;
      border-radius: 4px !important;
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--vscode-editor-foreground, #1a1a1a) !important;
    }
    table {
      border-color: var(--vscode-panel-border, #ccc) !important;
    }
    th, td {
      border-color: var(--vscode-panel-border, #ccc) !important;
    }
    /* Diagram SVGs: white background for readability on any theme */
    svg {
      background-color: #ffffff;
      border-radius: 4px;
      padding: 8px;
    }
    /* Proportional scaling for diagram SVGs with fixed width/height */
    svg {
      max-width: 100%;
      height: auto !important;
    }
    /* Markmap SVGs must fill their container, not collapse to auto */
    .markmap-container svg {
      height: 100% !important;
    }
    /* Left-align display math (MathML block math is centered by default) */
    math[display="block"] {
      display: block !important;
      text-align: left !important;
    }
  </style>`;

  // Inject our theme CSS just before </head>
  if (html.includes('</head>')) {
    return html.replace('</head>', themeCss + '</head>');
  }
  // Fallback: prepend
  return themeCss + html;
}
