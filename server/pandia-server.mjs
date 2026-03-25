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

async function render (content, { format = 'html', math = 'mathml', maxwidth = '60em', center_math = false } = {}) {
  const id = randomBytes(6).toString('hex')
  const workdir = join(tmpdir(), `pandia-render-${id}`)
  mkdirSync(workdir, { recursive: true })

  const infile = join(workdir, 'input.md')
  writeFileSync(infile, content)

  const env = { ...process.env, PANDIA_PARALLEL: '1' }

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
  const cssRules = [
    // SVG diagrams: white background for readability on any theme, responsive scaling
    'svg{background:#fff;border-radius:4px;padding:8px;max-width:100%;height:auto!important}',
    // Markmap SVGs fill their container (server-measured height)
    '.markmap-container svg{height:100%!important;background:none;padding:0}',
    // Math: proper fonts
    'math,math *{font-family:"STIX Two Math","STIX Two Text",STIXGeneral,"Cambria Math","Latin Modern Math",serif}',
  ]
  if (!center_math) {
    cssRules.push('math[display=block]{display:block!important;text-align:left!important}')
  }
  // Write CSS to a file to avoid shell-escaping issues with quotes in font names
  const headerFile = join(workdir, 'header.html')
  writeFileSync(headerFile, `<style>\n${cssRules.join('\n')}\n</style>`)
  cmd += ` -H "${headerFile}"`
  cmd += ` -V maxwidth="${maxwidth}"`
  cmd += ` -o "${outfile}" "${infile}"`

  await execAsync(cmd, { cwd: workdir, env })
  let html = readFileSync(outfile, 'utf-8')

  // Ensure all inline SVGs have a white background rect.
  // The Lua filter injects backgrounds for SVGs it produces, but some survive
  // without one after pandoc's --embed-resources inlining (DBML, D2).
  html = html.replace(/<svg([^>]*)>([\s\S]*?)<\/svg>/gi, (match, attrs, content) => {
    // Remove fixed width/height from inline style so CSS height:auto can work.
    // This must happen for ALL SVGs, even those that already have a background.
    attrs = attrs.replace(/style="([^"]*)"/, (_, s) => {
      const cleaned = s.replace(/\b(?:width|height)\s*:\s*[^;]+;?\s*/g, '').trim()
      return cleaned ? ` style="${cleaned}"` : ''
    })
    // Skip if the <svg> tag already has a background style
    if (/background\s*:\s*(?:white|#[Ff]{6}|#[Ff]{3})/i.test(attrs)) return `<svg${attrs}>${content}</svg>`
    // Skip if a white rect is already the first child
    if (/^\s*<rect\s[^>]*fill="(?:white|#[Ff]{6}|#[Ff]{3})"/i.test(content)) return match
    // Skip nested SVGs (D2 wraps <svg> inside <svg>) — only patch outermost
    // We detect nested SVGs by checking if content starts with another <svg>
    const trimmed = content.replace(/^\s+/, '')
    if (trimmed.startsWith('<svg')) {
      // This is a wrapper SVG (D2) — patch the inner SVG instead (handled by recursion)
      return match
    }
    // Build a background rect from viewBox or width/height
    let bgRect
    const vb = attrs.match(/viewBox="([^"]+)"/)
    if (vb) {
      const parts = vb[1].trim().split(/\s+/)
      if (parts.length === 4) {
        bgRect = `<rect x="${parts[0]}" y="${parts[1]}" width="${parts[2]}" height="${parts[3]}" fill="white"/>`
      }
    }
    if (!bgRect) {
      const w = attrs.match(/width="([^"]+)"/)
      const h = attrs.match(/height="([^"]+)"/)
      if (w && h) {
        bgRect = `<rect width="${w[1]}" height="${h[1]}" fill="white"/>`
      } else {
        bgRect = '<rect width="100%" height="100%" fill="white"/>'
      }
    }
    return `<svg${attrs}>\n${bgRect}${content}</svg>`
  })

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
