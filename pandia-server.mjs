// pandia-server.mjs — HTTP API for rendering Markdown to PDF/HTML
//
// Usage: node pandia-server.mjs [--port PORT]
// Env:   PANDIA_PORT (default: 3300)
//
// API:
//   POST /render
//     Body (form-urlencoded or JSON):
//       file  — input .md file path (relative to /data)
//       to    — comma-separated formats: html, pdf (default: html)
//     Returns: JSON { ok: true, files: ["example.html", ...] }
//
//   GET /health → 200 "ok"

import { createServer } from 'http'
import { execSync, exec } from 'child_process'
import { readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync, rmSync } from 'fs'
import { join } from 'path'
import { parse as parseQS } from 'querystring'
import { tmpdir } from 'os'
import { randomBytes } from 'crypto'

const PORT = parseInt(process.env.PANDIA_PORT || '3300')
const FILTER = '/usr/local/share/pandoc/filters/diagram-filter.lua'
const PANDOC_COMMON = `--lua-filter=${FILTER} --from=gfm+tex_math_dollars`

const VALID_FORMATS = new Set(['html', 'pdf'])

function parseBody (req) {
  return new Promise((resolve, reject) => {
    let body = ''
    req.on('data', chunk => { body += chunk })
    req.on('end', () => {
      const ct = req.headers['content-type'] || ''
      if (ct.includes('json')) {
        try { resolve(JSON.parse(body)) } catch { resolve({}) }
      } else {
        resolve(parseQS(body))
      }
    })
    req.on('error', reject)
  })
}

function buildCmd (file, fmt, base, maxwidth) {
  if (fmt === 'pdf') {
    return `pandoc ${PANDOC_COMMON} --to=pdf --pdf-engine=pdflatex`
      + ` -V geometry:margin=2.5cm --standalone -o "${base}.pdf" "${file}"`
  } else if (fmt === 'html') {
    return `pandoc ${PANDOC_COMMON} --to=html5 --standalone --mathjax`
      + ` -V maxwidth="${maxwidth || '60em'}" -o "${base}.html" "${file}"`
  }
  throw new Error(`Unknown format: ${fmt}`)
}

function execAsync (cmd, opts) {
  return new Promise((resolve, reject) => {
    exec(cmd, opts, (err, stdout, stderr) => {
      if (err) reject(err)
      else resolve(stdout)
    })
  })
}

async function render (file, formats, maxwidth) {
  const base = file.replace(/\.md$/, '')
  const env = { ...process.env, PANDIA_PARALLEL: '1' }
  const opts = { cwd: '/data', env }

  // Run all formats in parallel
  await Promise.all(formats.map(fmt =>
    execAsync(buildCmd(file, fmt, base, maxwidth), opts)
  ))

  return formats.map(fmt => `${base}.${fmt}`)
}

async function preview (content, { maxwidth = '60em' } = {}) {
  // Create isolated temp dir for this render
  const id = randomBytes(6).toString('hex')
  const workdir = join(tmpdir(), `pandia-preview-${id}`)
  mkdirSync(workdir, { recursive: true })

  const infile = join(workdir, 'input.md')
  const outfile = join(workdir, 'output.html')
  writeFileSync(infile, content)

  const env = { ...process.env, PANDIA_PARALLEL: '1' }

  // Use --mathml for server-side math rendering (no MathJax needed)
  // Use --embed-resources to inline all images as base64 data-URIs
  const cmd = `pandoc --lua-filter=${FILTER} --from=gfm+tex_math_dollars`
    + ` --to=html5 --mathml --embed-resources --standalone`
    + ` -V maxwidth="${maxwidth}"`
    + ` -o "${outfile}" "${infile}"`

  await execAsync(cmd, { cwd: workdir, env })

  const html = readFileSync(outfile, 'utf-8')

  // Clean up temp dir
  try { rmSync(workdir, { recursive: true }) } catch {}

  return html
}

function readRawBody (req) {
  return new Promise((resolve, reject) => {
    let body = ''
    req.on('data', chunk => { body += chunk })
    req.on('end', () => resolve(body))
    req.on('error', reject)
  })
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`)

  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' })
    return res.end('ok')
  }

  if (url.pathname === '/render' && req.method === 'POST') {
    try {
      const params = await parseBody(req)
      const file = params.file
      if (!file) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: 'Missing "file" parameter' }))
      }
      const formats = (params.to || 'html').split(',').map(s => s.trim())
      const invalid = formats.filter(f => !VALID_FORMATS.has(f))
      if (invalid.length > 0) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: `Invalid format: ${invalid.join(', ')}. Valid formats: html, pdf` }))
      }
      const maxwidth = params.maxwidth || '60em'
      const files = await render(file, formats, maxwidth)
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ ok: true, files }))
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
    }
    return
  }

  // Also support GET with query params for simple testing
  if (url.pathname === '/render' && req.method === 'GET') {
    try {
      const file = url.searchParams.get('file')
      if (!file) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: 'Missing "file" parameter' }))
      }
      const formats = (url.searchParams.get('to') || 'html').split(',').map(s => s.trim())
      const invalid = formats.filter(f => !VALID_FORMATS.has(f))
      if (invalid.length > 0) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: `Invalid format: ${invalid.join(', ')}. Valid formats: html, pdf` }))
      }
      const maxwidth = url.searchParams.get('maxwidth') || '60em'
      const files = await render(file, formats, maxwidth)
      res.writeHead(200, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ ok: true, files }))
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
    }
    return
  }

  if (url.pathname === '/preview' && req.method === 'POST') {
    try {
      const content = await readRawBody(req)
      if (!content.trim()) {
        res.writeHead(400, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: 'Empty request body — send Markdown as plain text' }))
      }
      const opts = {
        maxwidth: url.searchParams.get('maxwidth') || '60em',
      }
      const html = await preview(content, opts)
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
      res.end(html)
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ error: err.message }))
    }
    return
  }

  // Method not allowed
  if (url.pathname === '/preview' && req.method !== 'POST') {
    res.writeHead(405, { 'Content-Type': 'application/json', 'Allow': 'POST' })
    return res.end(JSON.stringify({ error: 'Method not allowed. Use POST.' }))
  }

  if (url.pathname === '/render' && !['GET', 'POST'].includes(req.method)) {
    res.writeHead(405, { 'Content-Type': 'application/json', 'Allow': 'GET, POST' })
    return res.end(JSON.stringify({ error: 'Method not allowed. Use GET or POST.' }))
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('not found')
})

server.listen(PORT, '0.0.0.0', () => {
  process.stderr.write(`pandia server ready on port ${PORT}\n`)
})
