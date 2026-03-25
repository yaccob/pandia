#!/usr/bin/env node
// markmap-render.mjs — Generate markmap HTML fragments or static images
//
// Usage:
//   node markmap-render.mjs --input <file.md> --output <file> --format <fmt> [--id <n>]
//
// Formats:
//   html-fragment  Self-contained HTML fragment for embedding (default)
//   png            Static PNG via headless Chromium (for PDF output)
//
// The --id flag sets a unique SVG ID to avoid collisions when multiple
// markmap blocks appear in one document.

import { readFileSync, writeFileSync, unlinkSync } from 'fs'
import { resolve, dirname, join } from 'path'
import { fileURLToPath } from 'url'
import { tmpdir } from 'os'

// Parse arguments
const args = process.argv.slice(2)
function getArg (name) {
  const i = args.indexOf(name)
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null
}

const inputFile = getArg('--input')
const outputFile = getArg('--output')
const format = getArg('--format') || 'html-fragment'
const svgId = getArg('--id') || '1'

if (!inputFile || !outputFile) {
  process.stderr.write('Usage: node markmap-render.mjs --input <file> --output <file> --format <fmt>\n')
  process.exit(1)
}

// Resolve markmap modules from markmap-cli installation
function resolveFromCli (mod) {
  // Try common locations
  const locations = [
    // Global npm (macOS Homebrew)
    `/opt/homebrew/lib/node_modules/markmap-cli/node_modules/${mod}`,
    // Global npm (Linux)
    `/usr/local/lib/node_modules/markmap-cli/node_modules/${mod}`,
    // Fallback: resolve from markmap-cli
    `markmap-cli/node_modules/${mod}`
  ]
  for (const loc of locations) {
    try {
      return require.resolve ? loc : loc
    } catch {}
  }
  return mod // let Node.js try default resolution
}

// Dynamic import with fallback paths
async function importMarkmap () {
  let Transformer, fillTemplate

  // Try to import from markmap-cli's node_modules
  const paths = [
    '/opt/homebrew/lib/node_modules/markmap-cli/node_modules',
    '/usr/local/lib/node_modules/markmap-cli/node_modules',
    '/usr/lib/node_modules/markmap-cli/node_modules'
  ]

  for (const base of paths) {
    try {
      const lib = await import(`${base}/markmap-lib/dist/index.js`)
      const render = await import(`${base}/markmap-render/dist/index.js`)
      Transformer = lib.Transformer
      fillTemplate = render.fillTemplate
      break
    } catch {}
  }

  if (!Transformer || !fillTemplate) {
    // Last resort: bare specifier
    const lib = await import('markmap-lib')
    const render = await import('markmap-render')
    Transformer = lib.Transformer
    fillTemplate = render.fillTemplate
  }

  return { Transformer, fillTemplate }
}

import { execSync } from 'child_process'
import { existsSync } from 'fs'

const BROWSER_WS_FILE = '/tmp/chromium-browser-ws.url'

function buildLaunchOpts () {
  const opts = { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
  // Use MMDC_PUPPETEER_CONFIG if set (mermaid-cli convention)
  const puppeteerConfig = process.env.MMDC_PUPPETEER_CONFIG
  if (puppeteerConfig) {
    try {
      Object.assign(opts, JSON.parse(readFileSync(puppeteerConfig, 'utf-8')))
    } catch {}
  }
  // Auto-detect system Chromium (e.g. in Alpine containers)
  if (!opts.executablePath) {
    for (const bin of ['/usr/bin/chromium-browser', '/usr/bin/chromium', '/usr/bin/google-chrome']) {
      try {
        execSync(`test -x ${bin}`, { stdio: 'ignore' })
        opts.executablePath = bin
        break
      } catch {}
    }
  }
  return opts
}

// Find local copies of d3/markmap-view to avoid CDN downloads during measurement
function findLocalAssets () {
  const bases = [
    '/opt/homebrew/lib/node_modules/markmap-cli',
    '/usr/local/lib/node_modules/markmap-cli',
    '/usr/lib/node_modules/markmap-cli'
  ]
  for (const base of bases) {
    const d3 = `${base}/node_modules/d3/dist/d3.min.js`
    const mmView = `${base}/node_modules/markmap-view/dist/browser/index.js`
    if (existsSync(d3) && existsSync(mmView)) return { d3, mmView }
  }
  return null
}

// Replace CDN <script src="..."> tags with inline <script> containing local file contents.
// Uses function replacements to avoid $-sign interpretation in d3.min.js.
function inlineLocalAssets (html) {
  const assets = findLocalAssets()
  if (!assets) return html
  const d3Code = readFileSync(assets.d3, 'utf-8')
  const mmCode = readFileSync(assets.mmView, 'utf-8')
  html = html.replace(
    /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/d3@[^"]*"><\/script>/,
    () => `<script>${d3Code}</script>`
  )
  html = html.replace(
    /<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/markmap-view@[^"]*"><\/script>/,
    () => `<script>${mmCode}</script>`
  )
  return html
}

// Try to connect to a shared Chromium instance (e.g. from mermaid-server),
// fall back to launching our own.
async function acquireBrowser (puppeteer) {
  if (existsSync(BROWSER_WS_FILE)) {
    try {
      const wsUrl = readFileSync(BROWSER_WS_FILE, 'utf-8').trim()
      const browser = await puppeteer.default.connect({ browserWSEndpoint: wsUrl })
      return { browser, shared: true }
    } catch {}
  }
  const browser = await puppeteer.default.launch(buildLaunchOpts())
  return { browser, shared: false }
}

async function releaseBrowser ({ browser, shared }) {
  if (shared) browser.disconnect()
  else await browser.close()
}

async function measureMarkmapLayout (root, scriptUrls) {
  // Render with Markmap.create in a tall container, then read the g element's
  // bounding box and scale factor. Returns { height, translateX, topY, scale }
  // so the fragment can set the container height and top-align the tree.
  const localAssets = findLocalAssets()
  let scriptTags = ''
  if (localAssets) {
    scriptTags += `<script>${readFileSync(localAssets.d3, 'utf-8')}</script>\n`
    scriptTags += `<script>${readFileSync(localAssets.mmView, 'utf-8')}</script>`
  } else {
    for (const url of scriptUrls) scriptTags += `<script src="${url}"></script>\n`
  }

  const html = `<!DOCTYPE html><html><head><style>body{margin:0;background:#fff}</style></head><body>
<div style="width:960px;height:4000px"><svg id="mm" style="width:100%;height:100%"></svg></div>
${scriptTags}
<script>markmap.Markmap.create("svg#mm", null, ${JSON.stringify(root)});</script>
</body></html>`

  const tmpHtml = join(tmpdir(), `markmap-measure-${Date.now()}.html`)
  writeFileSync(tmpHtml, html)

  const puppeteer = await loadPuppeteer()
  const handle = await acquireBrowser(puppeteer)
  const page = await handle.browser.newPage()
  await page.setViewport({ width: 960, height: 4000 })
  await page.goto(`file://${resolve(tmpHtml)}`, { waitUntil: 'networkidle0' })

  try {
    await page.waitForSelector('svg#mm g', { timeout: 10000 })
  } catch {
    await page.close()
    await releaseBrowser(handle)
    try { unlinkSync(tmpHtml) } catch {}
    return null
  }
  await new Promise(r => setTimeout(r, 500))

  // Screenshot and measure the 80% content window (ignoring sparse connector lines)
  const clip = { x: 0, y: 0, width: 960, height: 4000 }
  const imgData = await page.screenshot({ clip, encoding: 'base64' })

  const layout = await page.evaluate((imgData) => {
    const g = document.querySelector('svg#mm g')
    if (!g) return null
    const bbox = g.getBBox()
    const transform = g.getAttribute('transform') || ''
    const scaleMatch = transform.match(/scale\(([\d.]+)\)/)
    const translateMatch = transform.match(/translate\(([\d.]+)\s*,\s*([\d.]+)\)/)
    const scale = scaleMatch ? parseFloat(scaleMatch[1]) : 1
    const tx = translateMatch ? parseFloat(translateMatch[1]) : 0

    return new Promise(resolve => {
      const img = new Image()
      img.onload = () => {
        const canvas = document.createElement('canvas')
        canvas.width = img.width; canvas.height = img.height
        const ctx = canvas.getContext('2d')
        ctx.drawImage(img, 0, 0)
        const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data
        const w = canvas.width, h = canvas.height
        const rowCounts = []; let total = 0
        for (let y = 0; y < h; y++) {
          let count = 0
          for (let x = 0; x < w; x++) {
            const i = (y * w + x) * 4
            if ((255 - pixels[i]) + (255 - pixels[i+1]) + (255 - pixels[i+2]) > 30) count++
          }
          rowCounts.push(count); total += count
        }
        if (total === 0) { resolve(null); return }

        // 80% content window
        const target = total * 0.80
        let bestStart = 0, bestEnd = h - 1, bestSpan = h, wSum = 0, s = 0
        for (let e = 0; e < h; e++) {
          wSum += rowCounts[e]
          while (wSum >= target && s <= e) {
            if (e - s + 1 < bestSpan) { bestSpan = e - s + 1; bestStart = s; bestEnd = e }
            wSum -= rowCounts[s++]
          }
        }
        // topY: position tree so 80% content window starts at 20px from top
        const topY = Math.round(-bbox.y * scale - bestStart + 20)
        // utilization = fraction of container actually used by content
        const utilization = bestSpan / 4000
        resolve({ height: bestSpan + 40, utilization, scale, translateX: tx })
      }
      img.src = 'data:image/png;base64,' + imgData
    })
  }, imgData)

  await page.close()
  await releaseBrowser(handle)
  try { unlinkSync(tmpHtml) } catch {}
  return layout
}

async function generateHtmlFragment (content, id) {
  const { Transformer } = await importMarkmap()
  const t = new Transformer()
  const { root, features } = t.transform(content)
  const assets = t.getUsedAssets(features)

  // Build a self-contained HTML fragment with unique IDs
  const containerId = `markmap-${id}`
  const jsonData = JSON.stringify(root)

  // Extract script URLs from assets
  const scriptUrls = []
  if (assets?.scripts) {
    for (const s of assets.scripts) {
      if (s.type === 'script' && s.data?.src) {
        scriptUrls.push(s.data.src)
      }
    }
  }
  // Fallback to CDN URLs
  if (scriptUrls.length === 0) {
    scriptUrls.push(
      'https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js',
      'https://cdn.jsdelivr.net/npm/markmap-view'
    )
  }

  // Measure layout: visible content height and the whitespace offset
  const layout = await measureMarkmapLayout(root, scriptUrls)
  // The visible container height (what the user sees)
  const visibleHeight = layout ? layout.height : 400
  // Markmap uses ~60-70% of available space and centers. Give markmap enough
  // inner space so the content fills the visible container, then crop.
  // Small trees need more inner space (less efficient packing by markmap)
  const factor = visibleHeight < 300 ? 2.8 : 1.8
  const innerHeight = Math.ceil(visibleHeight * factor)
  const shiftUp = Math.round((innerHeight - visibleHeight) * 0.6)

  const fragment = `<div class="markmap-container" id="container-${containerId}" style="height:${visibleHeight}px;margin:1em 0;overflow:hidden">
<div style="height:${innerHeight}px;margin-top:-${shiftUp}px">
<svg id="${containerId}" style="width:100%;height:100%"></svg>
</div>
</div>
<script>
(function(){
  var scripts = ${JSON.stringify(scriptUrls)};
  var loaded = 0;
  function onReady() {
    var mm = window.markmap;
    if (mm && mm.Markmap) {
      mm.Markmap.create("svg#${containerId}", mm.deriveOptions ? mm.deriveOptions() : null, ${jsonData});
    }
  }
  function loadNext() {
    if (loaded >= scripts.length) { onReady(); return; }
    var existing = document.querySelector('script[src="' + scripts[loaded] + '"]');
    if (existing) { loaded++; loadNext(); return; }
    var s = document.createElement("script");
    s.src = scripts[loaded];
    s.onload = function() { loaded++; loadNext(); };
    document.head.appendChild(s);
  }
  if (window.markmap && window.markmap.Markmap) { onReady(); }
  else { loadNext(); }
})();
</script>`

  return fragment
}

async function loadPuppeteer () {
  let puppeteer
  const puppeteerEsmPaths = [
    '/opt/homebrew/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
    '/usr/local/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
    '/usr/local/lib/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
  ]
  try { puppeteer = await import('puppeteer') } catch {}
  if (!puppeteer) {
    for (const p of puppeteerEsmPaths) {
      try { puppeteer = await import(p); break } catch {}
    }
  }
  if (!puppeteer) {
    process.stderr.write('markmap SVG export requires puppeteer (install puppeteer or @mermaid-js/mermaid-cli)\n')
    process.exit(1)
  }
  return puppeteer
}

async function generatePdf (content, id, outputPath) {
  // Generate a full HTML page, render in headless browser, print to vector PDF
  const { Transformer, fillTemplate } = await importMarkmap()
  const t = new Transformer()
  const { root, features } = t.transform(content)
  const assets = t.getUsedAssets(features)
  const html = fillTemplate(root, assets)

  const tmpHtml = outputPath.replace(/\.[^.]+$/, '.html')
  writeFileSync(tmpHtml, html)

  const puppeteer = await loadPuppeteer()

  const handle = await acquireBrowser(puppeteer)
  const page = await handle.browser.newPage()
  await page.setViewport({ width: 1600, height: 1200 })
  await page.goto(`file://${resolve(tmpHtml)}`, { waitUntil: 'networkidle0' })

  await page.waitForSelector('svg#mindmap g', { timeout: 10000 })
  await new Promise(r => setTimeout(r, 500))

  // Fit the SVG precisely to its content and resize the page to match
  const dims = await page.evaluate(() => {
    const svg = document.querySelector('svg#mindmap')
    if (!svg) return null
    const g = svg.querySelector('g')
    if (!g) return null

    // Get the SVG-internal bounding box (unaffected by CSS transforms)
    const bbox = g.getBBox()
    const pad = 20

    // Set the SVG viewBox to tightly frame the content
    const vbX = bbox.x - pad
    const vbY = bbox.y - pad
    const vbW = bbox.width + 2 * pad
    const vbH = bbox.height + 2 * pad
    svg.setAttribute('viewBox', `${vbX} ${vbY} ${vbW} ${vbH}`)

    // Remove the centering transform so content sits at origin
    g.removeAttribute('transform')

    // Set explicit pixel dimensions on the SVG
    const width = Math.ceil(vbW)
    const height = Math.ceil(vbH)
    svg.style.width = width + 'px'
    svg.style.height = height + 'px'

    // Resize body to fit
    document.body.style.margin = '0'
    document.body.style.padding = '0'
    document.body.style.overflow = 'hidden'

    return { width, height }
  })

  if (!dims) {
    await page.close()
    await releaseBrowser(handle)
    try { unlinkSync(tmpHtml) } catch {}
    process.stderr.write('markmap error: failed to measure rendered content\n')
    process.exit(1)
  }

  // Resize viewport to content, then print to PDF at exact content size
  await page.setViewport({ width: dims.width, height: dims.height })
  await new Promise(r => setTimeout(r, 200))

  await page.pdf({
    path: outputPath,
    width: `${dims.width}px`,
    height: `${dims.height}px`,
    printBackground: true,
    margin: { top: '0px', right: '0px', bottom: '0px', left: '0px' }
  })

  await page.close()
  await releaseBrowser(handle)
  try { unlinkSync(tmpHtml) } catch {}
}

async function main () {
  const content = readFileSync(inputFile, 'utf-8')

  if (!content.trim()) {
    process.stderr.write('markmap error: empty input\n')
    process.exit(1)
  }

  if (format === 'html-fragment') {
    const fragment = await generateHtmlFragment(content, svgId)
    writeFileSync(outputFile, fragment)
  } else if (format === 'pdf') {
    await generatePdf(content, svgId, outputFile)
  } else {
    process.stderr.write(`markmap error: unknown format "${format}"\n`)
    process.exit(1)
  }
}

main().catch(err => {
  process.stderr.write(`markmap error: ${err.message}\n`)
  process.exit(1)
})
