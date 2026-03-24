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

// --- Test cases ---
const MARKMAP_MD = `# Test

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

let failures = 0

async function testMarkmapRendered (serverUrl) {
  const testName = 'markmap-rendered-successfully'

  const res = await httpPost(`${serverUrl}/render?math=mathml`, MARKMAP_MD)
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

async function testMarkmapHeight (serverUrl, html) {
  const testName = 'markmap-no-excessive-whitespace'

  if (!html) {
    console.log(`SKIP ${testName}: no HTML from previous test`)
    return
  }

  const puppeteer = await loadPuppeteer()
  const browser = await puppeteer.default.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  })
  const page = await browser.newPage()
  await page.setViewport({ width: 1200, height: 800 })

  await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(html), {
    waitUntil: 'networkidle0',
    timeout: 20000,
  })
  await new Promise(r => setTimeout(r, 3000))

  const result = await page.evaluate(() => {
    const container = document.querySelector('.markmap-container')
    const svg = container ? container.querySelector('svg') : null
    if (!container || !svg) return { error: 'markmap container or SVG not found' }

    const g = svg.querySelector('g')
    if (!g) return { error: 'SVG has no content (no <g> element)' }

    const containerRect = container.getBoundingClientRect()
    const contentBBox = g.getBBox()

    return {
      containerH: Math.round(containerRect.height),
      contentH: Math.round(contentBBox.height),
      ratio: (containerRect.height / contentBBox.height).toFixed(2),
    }
  })

  await browser.close()

  if (result.error) {
    console.log(`FAIL ${testName}: ${result.error}`)
    failures++
    return
  }

  const maxRatio = 1.5
  if (parseFloat(result.ratio) > maxRatio) {
    console.log(`FAIL ${testName}: container ${result.containerH}px is ${result.ratio}x the content height ${result.contentH}px (max ${maxRatio}x)`)
    failures++
  } else {
    console.log(`ok   ${testName}: container ${result.containerH}px, content ${result.contentH}px, ratio ${result.ratio}`)
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
  const html = await testMarkmapRendered(serverUrl)
  await testMarkmapHeight(serverUrl, html)
} finally {
  if (server) server.kill()
}

if (failures > 0) {
  console.log(`\n${failures} test(s) FAILED`)
  process.exit(1)
} else {
  console.log('\nAll diagram layout tests passed')
}
