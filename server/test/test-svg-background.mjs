#!/usr/bin/env node
// Visual test: all diagram SVGs must have a pandia-injected white background.
//
// Usage: node test/test-svg-background.mjs <html-file>
//
// Diagrams are embedded as <img src="data:image/svg+xml;base64,..."> or
// as inline <svg> elements. This test checks that every SVG has a white
// background <rect> as its first child (right after the <svg> tag),
// injected by the Lua filter's ensure_svg_background().

import { readFileSync } from 'fs'
import { resolve } from 'path'

const htmlFile = process.argv[2]
if (!htmlFile) {
  process.stderr.write('Usage: node test-svg-background.mjs <html-file>\n')
  process.exit(1)
}

const html = readFileSync(resolve(htmlFile), 'utf-8')

let pass = 0
let fail = 0

function ok (msg) { pass++; console.log(`  \x1b[32mPASS\x1b[0m ${msg}`) }
function ng (msg, detail) {
  fail++
  console.log(`  \x1b[31mFAIL\x1b[0m ${msg}`)
  if (detail) console.log(`       ${detail}`)
}

// Check if an SVG has a white/opaque background via any of these mechanisms:
// 1. A <rect fill="white"> as first child after <svg> (pandia-injected)
// 2. A style="...background:#FFFFFF..." on the <svg> tag itself (PlantUML)
// 3. A <polygon fill="white"> as first visual element (Graphviz, inside <g>)
// 4. A <rect fill="#FFFFFF"> as first visual element (D2, Kroki)
function svgHasOpaqueBackground (svgContent) {
  // Check 1: <rect fill="white"> as first child
  const afterSvg = svgContent.replace(/^[\s\S]*?<svg[^>]*>/, '')
  const trimmed = afterSvg.replace(/^\s+/, '')
  if (/^<rect\s[^>]*fill="(?:white|#[Ff]{6}|#[Ff]{3})"[^>]*\/?>/.test(trimmed)) return true

  // Check 2: background on <svg> style attribute
  const svgTag = svgContent.match(/<svg[^>]*>/)?.[0] || ''
  if (/style="[^"]*background\s*:\s*(?:white|#[Ff]{6}|#[Ff]{3})/.test(svgTag)) return true

  // Check 3 & 4: first visual element inside <g> or after skipping non-visual elements
  let remaining = trimmed
  for (let attempts = 0; attempts < 20; attempts++) {
    remaining = remaining.replace(/^\s+/, '')
    if (remaining.startsWith('<!--')) {
      remaining = remaining.replace(/^<!--[\s\S]*?-->/, '')
    } else if (remaining.match(/^<defs[\s>]/i)) {
      remaining = remaining.replace(/^<defs[\s\S]*?<\/defs>/i, '')
    } else if (remaining.match(/^<title[\s>]/i)) {
      remaining = remaining.replace(/^<title[\s\S]*?<\/title>/i, '')
    } else if (remaining.match(/^<desc[\s>]/i)) {
      remaining = remaining.replace(/^<desc[\s\S]*?<\/desc>/i, '')
    } else if (remaining.match(/^<style[\s>]/i)) {
      remaining = remaining.replace(/^<style[\s\S]*?<\/style>/i, '')
    } else if (remaining.match(/^<g[\s>]/i)) {
      remaining = remaining.replace(/^<g[^>]*>/, '')
    } else if (remaining.match(/^<svg[\s>]/i)) {
      // Nested SVG (e.g. D2) — check its style and enter it
      const innerSvgTag = remaining.match(/^<svg([^>]*)>/i)
      if (innerSvgTag && /background\s*:\s*(?:white|#[Ff]{6}|#[Ff]{3})/i.test(innerSvgTag[1])) return true
      remaining = remaining.replace(/^<svg[^>]*>/, '')
    } else {
      break
    }
  }
  if (/^<(?:rect|polygon)\s[^>]*fill="(?:white|#[Ff]{6}|#[Ff]{3})"[^>]*\/?>/.test(remaining)) return true

  return false
}

// Extract SVGs from base64 data URIs in <img> tags
const imgPattern = /src="data:image\/svg\+xml;base64,([^"]+)"/g
const svgs = []
let match
while ((match = imgPattern.exec(html)) !== null) {
  const decoded = Buffer.from(match[1], 'base64').toString('utf-8')
  const idMatch = decoded.match(/id="([^"]+)"/)
  const classMatch = decoded.match(/class="([^"]+)"/)
  svgs.push({ id: idMatch?.[1] || classMatch?.[1] || `img-svg-${svgs.length}`, content: decoded })
}

// Also extract inline <svg> elements
const inlineSvgPattern = /<svg[^>]*>[\s\S]*?<\/svg>/gi
while ((match = inlineSvgPattern.exec(html)) !== null) {
  const idMatch = match[0].match(/id="([^"]+)"/)
  svgs.push({ id: idMatch?.[1] || `inline-svg-${svgs.length}`, content: match[0] })
}

if (svgs.length === 0) {
  ok('no SVG diagrams found (nothing to check)')
} else {
  const noBg = svgs.filter(s => !svgHasOpaqueBackground(s.content))
  if (noBg.length === 0) {
    ok(`svg-opaque-background (${svgs.length} SVG(s) all have opaque backgrounds)`)
  } else {
    const names = noBg.map(s => s.id).join(', ')
    ng(`svg-opaque-background`, `${noBg.length} of ${svgs.length} SVG(s) lack opaque background: ${names}`)
  }
}

process.exit(fail)
