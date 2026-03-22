// Persistent mermaid render server for container use.
// Keeps a single Chromium instance alive across multiple render requests,
// avoiding repeated browser startup overhead (~2-3s per diagram).
//
// Usage: node mermaid-server.mjs
// Env:   MMDC_PUPPETEER_CONFIG — path to puppeteer JSON config
//        MERMAID_PORT          — server port (default: 3200)
//
// API:
//   GET /health              → 200 "ok"
//   GET /render?in=&out=&fmt= → renders diagram, writes to out, returns 200

import puppeteer from 'puppeteer'
import { renderMermaid } from './src/index.js'
import { readFileSync, writeFileSync } from 'fs'
import { createServer } from 'http'

const PORT = parseInt(process.env.MERMAID_PORT || '3200')
const configFile = process.env.MMDC_PUPPETEER_CONFIG

const puppeteerConfig = configFile
  ? JSON.parse(readFileSync(configFile, 'utf-8'))
  : {}

const browser = await puppeteer.launch({
  headless: true,
  executablePath: puppeteerConfig.executablePath,
  args: puppeteerConfig.args || []
})

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`)

  if (url.pathname === '/health') {
    res.writeHead(200)
    return res.end('ok')
  }

  if (url.pathname === '/render') {
    const infile = url.searchParams.get('in')
    const outfile = url.searchParams.get('out')
    const fmt = url.searchParams.get('fmt') || 'svg'

    try {
      const definition = readFileSync(infile, 'utf-8')
      const { data } = await renderMermaid(browser, definition, fmt, {})
      writeFileSync(outfile, data)
      res.writeHead(200)
      res.end('ok')
    } catch (err) {
      res.writeHead(500)
      res.end(err.message)
    }
    return
  }

  res.writeHead(404)
  res.end('not found')
})

server.listen(PORT, '127.0.0.1', () => {
  writeFileSync('/tmp/mermaid-server.ready', String(PORT))
  process.stderr.write(`Mermaid server ready on port ${PORT}\n`)
})
