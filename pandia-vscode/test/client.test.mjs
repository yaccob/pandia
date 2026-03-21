import { describe, it, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'

// We test against a mock server to avoid needing Docker for unit tests.
// Integration tests against the real container are in test/test-serve.sh.

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

      if (url.pathname === '/preview' && req.method === 'POST') {
        let body = ''
        req.on('data', c => { body += c })
        req.on('end', () => {
          if (!body.trim()) {
            res.writeHead(400, { 'Content-Type': 'application/json' })
            return res.end(JSON.stringify({ error: 'Empty body' }))
          }
          const maxwidth = url.searchParams.get('maxwidth') || '60em'
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
          res.end(`<html><body style="max-width:${maxwidth}"><h1>Mock</h1><p>${body}</p></body></html>`)
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

// Import after build — these tests run against the compiled output
const { PandiaClient } = await import('../out/client.js')

describe('PandiaClient', () => {
  it('checkHealth returns true for running server', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const ok = await client.checkHealth()
    assert.equal(ok, true)
  })

  it('checkHealth returns false for unreachable server', async () => {
    const client = new PandiaClient('http://localhost:19999')
    const ok = await client.checkHealth()
    assert.equal(ok, false)
  })

  it('preview returns HTML for valid markdown', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const html = await client.preview('# Hello')
    assert.ok(html.includes('Hello'))
    assert.ok(html.includes('<html>'))
  })

  it('preview passes maxwidth as query parameter', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    const html = await client.preview('# Test', { maxwidth: '40em' })
    assert.ok(html.includes('40em'))
  })

  it('preview throws on empty content', async () => {
    const client = new PandiaClient(`http://localhost:${mockPort}`)
    await assert.rejects(
      () => client.preview(''),
      /empty|400/i
    )
  })

  it('preview throws on unreachable server', async () => {
    const client = new PandiaClient('http://localhost:19999')
    await assert.rejects(
      () => client.preview('# Test')
    )
  })
})
