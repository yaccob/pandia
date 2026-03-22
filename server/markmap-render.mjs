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
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

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

async function generateHtmlFragment (content, id) {
  const { Transformer, fillTemplate } = await importMarkmap()
  const t = new Transformer()
  const { root, features } = t.transform(content)
  const assets = t.getUsedAssets(features)

  // Build a self-contained HTML fragment with unique IDs
  const containerId = `markmap-${id}`
  const jsonData = JSON.stringify(root)

  // Initial height is generous; the client script will measure the actual
  // rendered size (all nodes expanded) and shrink to fit.
  const initialHeight = 2000

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

  const fragment = `<div class="markmap-container" id="container-${containerId}" style="height:${initialHeight}px;margin:1em 0">
<svg id="${containerId}" style="width:100%;height:100%"></svg>
</div>
<script>
(function(){
  var scripts = ${JSON.stringify(scriptUrls)};
  var loaded = 0;
  function fitContainer() {
    // Measure actual rendered content and resize container to fit
    var svg = document.querySelector("svg#${containerId}");
    var g = svg && svg.querySelector("g");
    if (!g) return;
    var bbox = g.getBBox();
    var height = Math.max(400, Math.ceil(bbox.height + 40));
    var container = document.getElementById("container-${containerId}");
    if (container) container.style.height = height + "px";
  }
  var instance;
  function onReady() {
    var data = ${jsonData};
    var mm = window.markmap;
    if (mm && mm.Markmap) {
      instance = mm.Markmap.create("svg#${containerId}", mm.deriveOptions ? mm.deriveOptions() : null, data);
      // After render + animation: resize container then re-center tree
      setTimeout(function() {
        fitContainer();
        if (instance && instance.fit) instance.fit();
      }, 500);
    }
  }
  function loadNext() {
    if (loaded >= scripts.length) { onReady(); return; }
    // Skip if already loaded
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

  const puppeteerConfig = process.env.MMDC_PUPPETEER_CONFIG
  const launchOpts = { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
  if (puppeteerConfig) {
    try {
      const config = JSON.parse(readFileSync(puppeteerConfig, 'utf-8'))
      Object.assign(launchOpts, config)
    } catch {}
  }

  const browser = await puppeteer.default.launch(launchOpts)
  const page = await browser.newPage()
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
    await browser.close()
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

  await browser.close()
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
