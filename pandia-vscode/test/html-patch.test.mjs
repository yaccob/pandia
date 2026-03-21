import { describe, it } from 'node:test'
import assert from 'node:assert/strict'

const { patchHtmlForWebview } = await import('../out/html-patch.js')

describe('patchHtmlForWebview', () => {
  const sampleHtml = `<html><head><style>html{color:#1a1a1a;}</style></head>
    <body><h1>Test</h1>
    <svg width="200pt" height="100pt" viewBox="0 0 200 100"><rect/></svg>
    </body></html>`

  it('injects CSS before </head>', () => {
    const result = patchHtmlForWebview(sampleHtml)
    assert.ok(result.includes('<style>'))
    // Our injected style must come before </head>
    const styleIdx = result.lastIndexOf('<style>')
    const headIdx = result.indexOf('</head>')
    assert.ok(styleIdx < headIdx, 'injected CSS must be before </head>')
  })

  it('sets SVG background to white for dark-theme readability', () => {
    const result = patchHtmlForWebview(sampleHtml)
    assert.match(result, /svg\s*\{[^}]*background-color:\s*#ffffff/s,
      'SVGs must have a white background for readability on dark themes')
  })

  it('enables proportional SVG scaling with height:auto', () => {
    const result = patchHtmlForWebview(sampleHtml)
    assert.match(result, /svg\s*\{[^}]*height:\s*auto/s,
      'SVGs must have height:auto for proportional scaling')
  })

  it('sets max-width:100% on SVGs to prevent overflow', () => {
    const result = patchHtmlForWebview(sampleHtml)
    assert.match(result, /svg\s*\{[^}]*max-width:\s*100%/s,
      'SVGs must have max-width:100% to prevent horizontal overflow')
  })

  it('uses VS Code theme variables for text color', () => {
    const result = patchHtmlForWebview(sampleHtml)
    assert.match(result, /--vscode-editor-foreground/,
      'must use VS Code foreground variable')
    assert.match(result, /--vscode-editor-background/,
      'must use VS Code background variable')
  })

  it('left-aligns MathML display math', () => {
    const mathHtml = `<html><head></head><body>
      <math display="block"><mrow><mi>x</mi></mrow></math>
    </body></html>`
    const result = patchHtmlForWebview(mathHtml)
    assert.match(result, /math\[display="block"\][^}]*text-align:\s*left/s,
      'display math must be left-aligned')
  })

  it('does not override height of markmap SVGs', () => {
    const markmapHtml = `<html><head></head><body>
      <div class="markmap-container" style="height:800px">
        <svg id="markmap-1" style="width:100%;height:100%"></svg>
      </div>
    </body></html>`
    const result = patchHtmlForWebview(markmapHtml)
    // The height:auto must NOT apply to markmap SVGs (they need height:100% to fill container)
    assert.match(result, /\.markmap-container\s+svg[^}]*height:\s*100%/s,
      'markmap SVGs must keep height:100% to fill their container')
  })

  it('works without </head> tag (fallback)', () => {
    const noHead = '<h1>Hello</h1><svg width="50pt"></svg>'
    const result = patchHtmlForWebview(noHead)
    assert.ok(result.includes('<style>'), 'CSS must be prepended as fallback')
    assert.ok(result.includes('Hello'), 'original content preserved')
  })
})
