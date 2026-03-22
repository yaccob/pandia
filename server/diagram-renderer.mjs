#!/usr/bin/env node
// diagram-renderer.mjs — Render diagram types to SVG via npm packages
//
// Usage:
//   node diagram-renderer.mjs --type <type> --input <file> --output <file.svg>
//
// Supported types:
//   nomnoml    — UML-like diagrams
//   dbml       — Database diagrams (DBML syntax)
//   d2         — D2 declarative diagrams
//   wavedrom   — Digital timing diagrams (WaveJSON)

import { readFileSync, writeFileSync } from 'fs'
import { execSync } from 'child_process'

// Parse arguments
const args = process.argv.slice(2)
function getArg (name) {
  const i = args.indexOf(name)
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null
}

const type = getArg('--type')
const inputFile = getArg('--input')
const outputFile = getArg('--output')

if (!type || !inputFile || !outputFile) {
  process.stderr.write('Usage: node diagram-renderer.mjs --type <type> --input <file> --output <file.svg>\n')
  process.stderr.write('Types: nomnoml, dbml, d2, wavedrom\n')
  process.exit(1)
}

const content = readFileSync(inputFile, 'utf-8')
if (!content.trim()) {
  process.stderr.write(`diagram-renderer error: empty input for type "${type}"\n`)
  process.exit(1)
}

async function renderNomnoml (src) {
  const nomnoml = await import('nomnoml')
  return nomnoml.default.renderSvg(src)
}

async function renderDbml (src) {
  const mod = await import('@softwaretechnik/dbml-renderer')
  const run = mod.default?.run || mod.run
  return run(src, 'svg')
}

async function renderD2 (src) {
  // Use d2 CLI binary (Go)
  const result = execSync('d2 - -', { input: src, maxBuffer: 10 * 1024 * 1024 })
  return result.toString()
}

async function renderWavedrom (src) {
  const wavedrom = (await import('wavedrom')).default
  const waveJson = JSON.parse(src)
  const tree = wavedrom.renderAny(0, waveJson, wavedrom.waveSkin)
  return wavedrom.onml.stringify(tree)
}

const renderers = {
  nomnoml: renderNomnoml,
  dbml: renderDbml,
  d2: renderD2,
  wavedrom: renderWavedrom,
}

async function main () {
  const renderer = renderers[type]
  if (!renderer) {
    process.stderr.write(`diagram-renderer error: unsupported type "${type}"\n`)
    process.stderr.write(`Supported types: ${Object.keys(renderers).join(', ')}\n`)
    process.exit(1)
  }

  const svg = await renderer(content)
  writeFileSync(outputFile, svg)
}

main().catch(err => {
  process.stderr.write(`diagram-renderer error (${type}): ${err.message}\n`)
  process.exit(1)
})
