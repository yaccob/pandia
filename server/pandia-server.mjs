// pandia-server.mjs — HTTP API for rendering Markdown to HTML/PDF
//
// Usage: node pandia-server.mjs [--port PORT]
// Env:   PANDIA_PORT (default: 3300)
//
// API:
//   POST /render
//     Body: Markdown content (plain text)
//     Query parameters:
//       format        — html (default) or pdf
//       math          — mathml (default) or mathjax
//       maxwidth      — max content width for HTML (default: 60em)
//       center_math   — true to center display math (default: left-aligned)
//       kroki_server  — Kroki server URL for additional diagram types
//     Response: rendered HTML or PDF (direct content, not JSON)
//
//   GET /health → 200 "ok"

import { createServer } from 'http'
import { exec } from 'child_process'
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'fs'
import { join, dirname } from 'path'
import { tmpdir } from 'os'
import { randomBytes } from 'crypto'
import { fileURLToPath } from 'url'

const PORT = parseInt(process.env.PANDIA_PORT || '3300')

// Find diagram-filter.lua: relative to this script, or container path
const __dirname = dirname(fileURLToPath(import.meta.url))
const FILTER = [
  join(__dirname, 'diagram-filter.lua'),
  '/usr/local/share/pandoc/filters/diagram-filter.lua',
  join(__dirname, '..', 'share', 'pandia', 'diagram-filter.lua'),
].find(p => existsSync(p)) || '/usr/local/share/pandoc/filters/diagram-filter.lua'

function execAsync (cmd, opts) {
  return new Promise((resolve, reject) => {
    exec(cmd, { ...opts, maxBuffer: 50 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) reject(err)
      else resolve(stdout)
    })
  })
}

function readRawBody (req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    req.on('data', chunk => chunks.push(chunk))
    req.on('end', () => resolve(Buffer.concat(chunks).toString()))
    req.on('error', reject)
  })
}

async function render (content, { format = 'html', math = 'mathml', maxwidth = '60em', center_math = false, kroki_server } = {}) {
  const id = randomBytes(6).toString('hex')
  const workdir = join(tmpdir(), `pandia-render-${id}`)
  mkdirSync(workdir, { recursive: true })

  const infile = join(workdir, 'input.md')
  writeFileSync(infile, content)

  const env = { ...process.env, PANDIA_PARALLEL: '1' }
  if (kroki_server) env.PANDIA_KROKI_URL = kroki_server

  let cmd = `pandoc --lua-filter=${FILTER} --from=gfm+tex_math_dollars --standalone`

  if (format === 'pdf') {
    const outfile = join(workdir, 'output.pdf')
    cmd += ` --to=pdf --pdf-engine=pdflatex -V geometry:margin=2.5cm`
    if (!center_math) cmd += ` -V classoption=fleqn`
    cmd += ` -o "${outfile}" "${infile}"`
    await execAsync(cmd, { cwd: workdir, env })
    const pdf = readFileSync(outfile)
    try { rmSync(workdir, { recursive: true }) } catch {}
    return { contentType: 'application/pdf', body: pdf }
  }

  // HTML — always use --embed-resources for self-contained output (inline SVGs).
  // Both math engines use --mathml for pandoc rendering. For mathjax mode,
  // the MathJax CDN script is injected after rendering — MathJax processes
  // the <math> tags client-side and replaces them with its own rendering.
  const outfile = join(workdir, 'output.html')
  cmd += ` --embed-resources --to=html5 --mathml`
  if (!center_math) {
    cmd += ` -V "header-includes=<style>math[display=block]{display:block!important;text-align:left!important}</style>"`
  }
  cmd += ` -V maxwidth="${maxwidth}"`
  cmd += ` -o "${outfile}" "${infile}"`

  await execAsync(cmd, { cwd: workdir, env })
  let html = readFileSync(outfile, 'utf-8')

  if (math === 'mathjax') {
    // Inject MathJax CDN script before </body> — it will find and render <math> tags
    const mathjaxConfig = center_math ? '' : `<script>window.MathJax={chtml:{displayAlign:'left'}};</script>\n`
    const mathjaxScript = `${mathjaxConfig}<script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>`
    html = html.replace('</body>', `${mathjaxScript}\n</body>`)
  }
  try { rmSync(workdir, { recursive: true }) } catch {}
  return { contentType: 'text/html; charset=utf-8', body: html }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`)

  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' })
    return res.end('ok')
  }

  if (url.pathname === '/render' && req.method === 'POST') {
    try {
      const content = await readRawBody(req)
      if (!content.trim()) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: 'Empty request body — send Markdown as plain text' }))
      }

      const format = url.searchParams.get('format') || 'html'
      if (format !== 'html' && format !== 'pdf') {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: `Invalid format: ${format}. Use html or pdf.` }))
      }

      const opts = {
        format,
        math: url.searchParams.get('math') || 'mathml',
        maxwidth: url.searchParams.get('maxwidth') || '60em',
        center_math: url.searchParams.get('center_math') === 'true',
        kroki_server: url.searchParams.get('kroki_server') || undefined,
      }

      const result = await render(content, opts)
      res.writeHead(200, { 'Content-Type': result.contentType })
      res.end(result.body)
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
    }
    return
  }

  if (url.pathname === '/render' && req.method !== 'POST') {
    res.writeHead(405, { 'Content-Type': 'application/json', 'Allow': 'POST' })
    return res.end(JSON.stringify({ error: 'Method not allowed. Use POST.' }))
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('not found')
})

server.listen(PORT, '0.0.0.0', () => {
  process.stderr.write(`pandia server ready on port ${PORT}\n`)
})
