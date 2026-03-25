import { describe, it, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'

// Mock server simulating the pandia /render and /health endpoints.
// Integration tests against the real container are in test/test-container.sh.

let mockServer
let mockPort

function startMockServer () {
  return new Promise(resolve => {
    mockServer = createServer((req, res) => {
      const url = new URL(req.url, `http://localhost:${mockPort}`)

      if (url.pathname === '/health') {
        res.writeHead(200, { 'Content-Type': 'text/plain' })
        return res.end('ok')
      }

      if (url.pathname === '/render' && req.method === 'POST') {
        let body = ''
        req.on('data', c => { body += c })
        req.on('end', () => {
          if (!body.trim()) {
            res.writeHead(400, { 'Content-Type': 'application/json' })
            return res.end(JSON.stringify({ error: 'Empty body' }))
          }
          const format = url.searchParams.get('format') || 'html'
          const math = url.searchParams.get('math') || 'mathjax'
          const maxwidth = url.searchParams.get('maxwidth') || '60em'
          if (format === 'pdf') {
            res.writeHead(200, { 'Content-Type': 'application/pdf' })
            return res.end('%PDF-mock')
          }
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
          res.end(`<html><body style="max-width:${maxwidth}" data-math="${math}"><h1>Mock</h1><p>${body}</p></body></html>`)
        })
        return
      }

      res.writeHead(404)
      res.end('not found')
    })
    mockServer.listen(0, () => {
      mockPort = mockServer.address().port
      resolve()
    })
  })
}

before(async () => {
  await startMockServer()
})

after(() => {
  mockServer.close()
})

const { PandiaClient } = await import('../out/client.js')

describe('PandiaClient', () => {
  it('checkHealth returns true for running server', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    assert.equal(await client.checkHealth(), true)
  })

  it('checkHealth returns false for unreachable server', async () => {
    const client = new PandiaClient('http://localhost:19999')
    assert.equal(await client.checkHealth(), false)
  })

  it('render returns HTML for valid markdown', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const html = await client.render('# Hello')
    assert.ok(html.includes('Hello'))
    assert.ok(html.includes('<html>'))
  })

  it('render passes format parameter', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const pdf = await client.render('# Test', { format: 'pdf' })
    assert.ok(pdf.includes('%PDF'))
  })

  it('render passes math parameter', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const html = await client.render('# Test', { math: 'mathml' })
    assert.ok(html.includes('data-math="mathml"'))
  })

  it('render passes maxwidth parameter', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const html = await client.render('# Test', { maxwidth: '40em' })
    assert.ok(html.includes('40em'))
  })

  it('render throws on empty content', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    await assert.rejects(() => client.render(''), /empty|400/i)
  })

  it('render throws on unreachable server', async () => {
    const client = new PandiaClient('http://localhost:19999')
    await assert.rejects(() => client.render('# Test'))
  })
})
