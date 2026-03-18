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
import { readFileSync } from 'fs'
import { parse as parseQS } from 'querystring'

const PORT = parseInt(process.env.PANDIA_PORT || '3300')
const FILTER = '/usr/local/share/pandoc/filters/diagram-filter.lua'
const PANDOC_COMMON = `--lua-filter=${FILTER} --from=gfm+tex_math_dollars`

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

  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('not found')
})

server.listen(PORT, '0.0.0.0', () => {
  process.stderr.write(`pandia server ready on port ${PORT}\n`)
})
