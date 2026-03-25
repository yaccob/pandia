#!/usr/bin/env node
// Visual diagram layout tests — uses headless Chromium to verify
// that rendered diagrams don't waste excessive vertical space.
//
// Starts its own local pandia-serve on a free port, renders test content,
// then measures layout in headless Chromium.

import { createServer } from 'net'
import { spawn } from 'child_process'
import { resolve } from 'path'
import { fileURLToPath } from 'url'
import { dirname } from 'path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)
const projectRoot = resolve(__dirname, '../..')

// --- Find a free port ---
async function getFreePort () {
  return new Promise((resolve, reject) => {
    const srv = createServer()
    srv.listen(0, () => {
      const port = srv.address().port
      srv.close(() => resolve(port))
    })
    srv.on('error', reject)
  })
}

// --- Puppeteer loading ---
async function loadPuppeteer () {
  let puppeteer
  const paths = [
    '/opt/homebrew/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
    '/usr/local/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
    '/usr/local/lib/node_modules/puppeteer/lib/esm/puppeteer/puppeteer.js',
  ]
  try { puppeteer = await import('puppeteer') } catch {}
  if (!puppeteer) {
    for (const p of paths) {
      try { puppeteer = await import(p); break } catch {}
    }
  }
  if (!puppeteer) {
    process.stderr.write('SKIP: puppeteer not available\n')
    process.exit(0)
  }
  return puppeteer
}

// --- HTTP helper ---
async function httpPost (url, body) {
  const mod = await import('http')
  return new Promise((resolve, reject) => {
    const req = mod.request(url, { method: 'POST', timeout: 30000 }, (res) => {
      let data = ''
      res.on('data', c => { data += c })
      res.on('end', () => resolve({ status: res.statusCode, body: data }))
    })
    req.on('error', reject)
    req.write(body)
    req.end()
  })
}

// --- Start local server ---
async function startServer (port) {
  const serverScript = resolve(projectRoot, 'cli/bin/pandia-serve')
  const child = spawn(serverScript, [String(port)], {
    cwd: projectRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  // Wait for health check
  for (let i = 0; i < 30; i++) {
    try {
      const mod = await import('http')
      const ok = await new Promise((resolve) => {
        const req = mod.get(`http://localhost:${port}/health`, (res) => {
          let d = ''
          res.on('data', c => { d += c })
          res.on('end', () => resolve(res.statusCode === 200))
        })
        req.on('error', () => resolve(false))
        req.setTimeout(1000, () => { req.destroy(); resolve(false) })
      })
      if (ok) return child
    } catch {}
    await new Promise(r => setTimeout(r, 1000))
  }
  child.kill()
  throw new Error('Server did not start within 30s')
}

// --- Test data ---
const MARKMAP_SMALL = `# Test

\`\`\`markmap
# Software Architecture
## Frontend
### React
### Vue.js
## Backend
### Node.js
### Go
\`\`\`

After markmap.
`

const MARKMAP_LARGE = `# Test

\`\`\`markmap
# Software Architecture
## Frontend
### Framework
#### React
#### Vue.js
#### Angular
### Build Tools
#### Vite
#### Webpack
### Testing
#### Jest
#### Cypress
## Backend
### Languages
#### TypeScript / Node.js
#### Python
#### Go
### Databases
#### PostgreSQL
#### Redis
#### MongoDB
### API
#### REST
#### GraphQL
## Infrastructure
### Containers
#### Docker
#### Kubernetes
### CI/CD
#### GitHub Actions
#### GitLab CI
### Monitoring
#### Prometheus
#### Grafana
\`\`\`

After markmap.
`

let failures = 0

async function testMarkmapRendered (serverUrl, markdown, label) {
  const testName = `markmap-rendered-${label}`

  const res = await httpPost(`${serverUrl}/render?math=mathml`, markdown)
  if (res.status !== 200) {
    console.log(`FAIL ${testName}: server returned ${res.status}`)
    failures++
    return null
  }

  const html = res.body

  // Check that markmap was rendered, not an error message
  if (html.includes('markmap error') || html.includes('markmap-render.mjs failed')) {
    console.log(`FAIL ${testName}: server returned error instead of rendered markmap`)
    failures++
    return null
  }

  // Check that the HTML contains a markmap container with an SVG
  if (!html.includes('markmap-container')) {
    console.log(`FAIL ${testName}: no markmap container in HTML`)
    failures++
    return null
  }

  if (!html.includes('markmap-') || !html.includes('<svg')) {
    console.log(`FAIL ${testName}: no markmap SVG in HTML`)
    failures++
    return null
  }

  console.log(`ok   ${testName}`)
  return html
}

async function testMarkmapHeight (serverUrl, html, label) {
  const testName = `markmap-no-excessive-whitespace-${label}`

  if (!html) {
    console.log(`SKIP ${testName}: no HTML from previous test`)
    return
  }

  const puppeteer = await loadPuppeteer()
  const dpr = 2
  const browser = await puppeteer.default.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  })
  const page = await browser.newPage()
  await page.setViewport({ width: 1400, height: 8000, deviceScaleFactor: dpr })

  await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(html), {
    waitUntil: 'networkidle0',
    timeout: 30000,
  })
  await new Promise(r => setTimeout(r, 5000))

  // Take a screenshot of the markmap container and scan pixel rows to find
  // where visible content starts and ends — this is what a human perceives.
  const clip = await page.evaluate(() => {
    const c = document.querySelector('.markmap-container')
    if (!c) return null
    const r = c.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) }
  })

  if (!clip) {
    console.log(`FAIL ${testName}: markmap container not found`)
    failures++
    await browser.close()
    return
  }

  // Screenshot returns a PNG buffer; decode it via page canvas to scan pixels
  const screenshotBase64 = await page.screenshot({ clip, encoding: 'base64' })

  const result = await page.evaluate(async (imgData, containerH, dpr) => {
    // Load screenshot into an Image, draw onto canvas, scan rows
    const img = new Image()
    await new Promise((resolve, reject) => {
      img.onload = resolve
      img.onerror = reject
      img.src = 'data:image/png;base64,' + imgData
    })
    const canvas = document.createElement('canvas')
    canvas.width = img.width
    canvas.height = img.height
    const ctx = canvas.getContext('2d')
    ctx.drawImage(img, 0, 0)
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data

    // Count non-white pixels per row to build a content density histogram.
    // Then find the smallest contiguous window containing 80% of all content
    // pixels — this matches human perception (ignores sparse connector lines
    // at the edges, focuses on where the dense text labels are).
    const colorThreshold = 30
    const rowCounts = []
    let totalContent = 0

    for (let y = 0; y < canvas.height; y++) {
      let count = 0
      for (let x = 0; x < canvas.width; x++) {
        const i = (y * canvas.width + x) * 4
        const r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
        if ((255 - r) + (255 - g) + (255 - b) > colorThreshold) count++
      }
      rowCounts.push(count)
      totalContent += count
    }

    if (totalContent === 0) return { error: 'no visible content pixels found' }

    // Sliding window: smallest span containing 80% of content pixels
    const target = totalContent * 0.80
    let bestStart = 0, bestEnd = canvas.height - 1, bestSpan = canvas.height
    let windowSum = 0, start = 0
    for (let end = 0; end < canvas.height; end++) {
      windowSum += rowCounts[end]
      while (windowSum >= target && start <= end) {
        const span = end - start + 1
        if (span < bestSpan) {
          bestSpan = span
          bestStart = start
          bestEnd = end
        }
        windowSum -= rowCounts[start]
        start++
      }
    }

    const visibleContentH = Math.round(bestSpan / dpr)
    return {
      containerH,
      visibleContentH,
      whiteAbove: Math.round(bestStart / dpr),
      whiteBelow: Math.round((canvas.height - bestEnd - 1) / dpr),
      ratio: (containerH / visibleContentH).toFixed(2),
    }
  }, screenshotBase64, clip.height, dpr)

  await browser.close()

  if (result.error) {
    console.log(`FAIL ${testName}: ${result.error}`)
    failures++
    return
  }

  // Pass if either: ratio ≤ 1.3, or whitespace above ≤ 40px (small trees have inherent padding)
  const maxRatio = 1.3
  const maxWhiteAbove = 40
  const ratioOk = parseFloat(result.ratio) <= maxRatio
  const whiteOk = result.whiteAbove <= maxWhiteAbove
  if (ratioOk || whiteOk) {
    console.log(`ok   ${testName}: container ${result.containerH}px, visible content ${result.visibleContentH}px, ratio ${result.ratio}, white above: ${result.whiteAbove}px`)
  } else {
    console.log(`FAIL ${testName}: container ${result.containerH}px but visible content only ${result.visibleContentH}px (ratio ${result.ratio}x, white above: ${result.whiteAbove}px, max: ratio ${maxRatio}x or white above ${maxWhiteAbove}px)`)
    failures++
  }
}

// --- Main ---
const externalUrl = process.argv[2]
let server = null
let serverUrl

if (externalUrl) {
  // Use provided server URL (e.g. from test-container.sh)
  serverUrl = externalUrl
  console.log(`Using external server at ${serverUrl}`)
} else {
  // Start own local server on a free port
  const port = await getFreePort()
  console.log(`Starting local server on port ${port}...`)
  server = await startServer(port)
  serverUrl = `http://localhost:${port}`
}

try {
  const htmlSmall = await testMarkmapRendered(serverUrl, MARKMAP_SMALL, 'small')
  await testMarkmapHeight(serverUrl, htmlSmall, 'small')

  const htmlLarge = await testMarkmapRendered(serverUrl, MARKMAP_LARGE, 'large')
  await testMarkmapHeight(serverUrl, htmlLarge, 'large')
} finally {
  if (server) server.kill()
}

if (failures > 0) {
  console.log(`\n${failures} test(s) FAILED`)
  process.exit(1)
} else {
  console.log('\nAll diagram layout tests passed')
}
