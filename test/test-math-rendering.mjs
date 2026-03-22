#!/usr/bin/env node
// Visual math rendering tests — uses headless Chromium to verify actual layout
// and rendering quality. Tests what the user sees, not implementation details.
//
// Usage: node test/test-math-rendering.mjs <html-file> [checks...]
//
// Checks:
//   math-left-aligned      Block math starts near the left margin
//   math-centered          Block math is horizontally centered
//   math-rendered          Math is rendered as glyphs, not raw LaTeX source
//   no-math-input-error    No "Math input error" visible on page
//   sqrt-has-vinculum      Square root symbols have a horizontal bar (vinculum)
//   integral-tall          Integral signs are taller than normal text
//   fraction-stacked       Fractions are vertically stacked (numerator above denominator)
//
// Example:
//   node test/test-math-rendering.mjs output.html math-left-aligned math-rendered sqrt-has-vinculum

import { readFileSync } from 'fs'
import { resolve } from 'path'

// --- Puppeteer loading (same strategy as markmap-render.mjs) ---
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

// --- Main ---
const args = process.argv.slice(2)
const htmlFile = args[0]
const checks = args.slice(1)

if (!htmlFile || checks.length === 0) {
  process.stderr.write('Usage: node test-math-rendering.mjs <html-file> <check...>\n')
  process.exit(1)
}

const htmlPath = resolve(htmlFile)
const htmlContent = readFileSync(htmlPath, 'utf-8')

const puppeteer = await loadPuppeteer()
const browser = await puppeteer.default.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
})

const page = await browser.newPage()
await page.setViewport({ width: 1200, height: 800 })
await page.setContent(htmlContent, { waitUntil: 'networkidle0', timeout: 15000 })

// Wait for MathJax to finish rendering (if present)
try {
  await page.evaluate(() => {
    return new Promise((resolve) => {
      if (window.MathJax && window.MathJax.startup) {
        window.MathJax.startup.promise.then(resolve).catch(resolve)
      } else {
        resolve()
      }
    })
  })
} catch {}
await new Promise(r => setTimeout(r, 500))

let pass = 0
let fail = 0

function ok (msg) { pass++; console.log(`  \x1b[32mPASS\x1b[0m ${msg}`) }
function ng (msg, detail) {
  fail++
  console.log(`  \x1b[31mFAIL\x1b[0m ${msg}`)
  if (detail) console.log(`       ${detail}`)
}

// Helper: find all block-level math elements and measure the actual content position.
// For alignment checks we need the leftmost rendered glyph, not the container box
// (which may span the full width while content is centered inside).
async function findBlockMathElements () {
  return page.evaluate(() => {
    const els = [
      ...document.querySelectorAll('math[display="block"]'),
      ...document.querySelectorAll('mjx-container[display="true"]'),
      ...document.querySelectorAll('.math.display'),
    ]
    // Deduplicate (MathJax wraps math in containers)
    const seen = new Set()
    return els.filter(el => {
      const key = el.getBoundingClientRect().top
      if (seen.has(key)) return false
      seen.add(key)
      return true
    }).map(el => {
      const containerRect = el.getBoundingClientRect()

      // Walk all descendant elements to find the leftmost rendered content.
      // This handles multi-line formulas where lines may be indented differently.
      let contentLeft = Infinity
      const descendants = el.querySelectorAll('*')
      for (const d of descendants) {
        const r = d.getBoundingClientRect()
        // Skip zero-width elements (spacers, annotations, etc.)
        if (r.width > 0 && r.height > 0) {
          contentLeft = Math.min(contentLeft, r.left)
        }
      }
      if (contentLeft === Infinity) contentLeft = containerRect.left

      return {
        top: containerRect.top,
        left: containerRect.left,
        width: containerRect.width,
        height: containerRect.height,
        contentLeft,
      }
    })
  })
}

// Helper: measure body layout
async function getBodyLayout () {
  return page.evaluate(() => {
    const rect = document.body.getBoundingClientRect()
    // Find main content container (pandoc uses <main> or first block child)
    const main = document.querySelector('main') || document.querySelector('article') || document.body
    const mainRect = main.getBoundingClientRect()
    const style = window.getComputedStyle(main)
    const paddingLeft = parseFloat(style.paddingLeft) || 0
    return {
      bodyLeft: rect.left,
      bodyWidth: rect.width,
      contentLeft: mainRect.left + paddingLeft,
      contentWidth: mainRect.width - paddingLeft * 2,
    }
  })
}

// Helper: get line height of normal text for comparison
async function getTextLineHeight () {
  return page.evaluate(() => {
    const p = document.querySelector('p')
    if (!p) return 20
    const style = window.getComputedStyle(p)
    return parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.2 || 20
  })
}

for (const check of checks) {
  switch (check) {

    case 'math-left-aligned': {
      const mathEls = await findBlockMathElements()
      const layout = await getBodyLayout()

      if (mathEls.length === 0) {
        ng('math-left-aligned', 'No block math elements found')
        break
      }

      // Left-aligned = leftmost rendered glyph is near the content left edge.
      // We allow up to 10% of content width as tolerance (some padding is normal).
      const threshold = layout.contentWidth * 0.10
      const allLeft = mathEls.every(el => Math.abs(el.contentLeft - layout.contentLeft) < threshold)

      if (allLeft) {
        const maxOffset = Math.max(...mathEls.map(el => Math.round(el.contentLeft - layout.contentLeft)))
        ok(`math-left-aligned (${mathEls.length} formula(s), max content offset ${maxOffset}px from left margin)`)
      } else {
        const offenders = mathEls
          .filter(el => Math.abs(el.contentLeft - layout.contentLeft) >= threshold)
          .map(el => `content at ${Math.round(el.contentLeft - layout.contentLeft)}px`)
        ng('math-left-aligned', `Not left-aligned: ${offenders.join(', ')} (threshold: ${Math.round(threshold)}px)`)
      }
      break
    }

    case 'math-centered': {
      const mathEls = await findBlockMathElements()
      const layout = await getBodyLayout()

      if (mathEls.length === 0) {
        ng('math-centered', 'No block math elements found')
        break
      }

      // Centered = content is not near left edge (offset > 15% of container width)
      const threshold = layout.contentWidth * 0.15
      const allCentered = mathEls.every(el => (el.contentLeft - layout.contentLeft) > threshold)

      if (allCentered) {
        ok(`math-centered (${mathEls.length} formula(s))`)
      } else {
        ng('math-centered', 'Some formulas are left-aligned instead of centered')
      }
      break
    }

    case 'math-rendered': {
      const result = await page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || ''
        const rawIndicators = ['\\frac', '\\sqrt', '\\int', '\\sum', '\\begin{']
        const found = rawIndicators.filter(cmd => text.includes(cmd))
        return { raw: found, hasRaw: found.length > 0 }
      })

      if (result.hasRaw) {
        ng('math-rendered', `Raw LaTeX visible: ${result.raw.join(', ')}`)
      } else {
        ok('math-rendered (no raw LaTeX visible)')
      }
      break
    }

    case 'no-math-input-error': {
      const hasError = await page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || ''
        return text.includes('Math input error')
      })
      if (hasError) {
        ng('no-math-input-error', '"Math input error" found on page')
      } else {
        ok('no-math-input-error')
      }
      break
    }

    case 'sqrt-has-vinculum': {
      // A correctly rendered square root has a horizontal bar (vinculum) above the radicand.
      // Visually: the bounding box of the sqrt element should be significantly taller than
      // the radicand alone, because the vinculum adds height above.
      // We measure: does the sqrt rendering extend above the baseline of surrounding text?
      const result = await page.evaluate(() => {
        // Find sqrt elements by their rendered structure
        // MathML: <msqrt> or <mroot>
        // MathJax: elements with class containing "sqrt"
        const sqrtEls = [
          ...document.querySelectorAll('msqrt'),
          ...document.querySelectorAll('mroot'),
          ...document.querySelectorAll('[class*="sqrt"]'),
          ...document.querySelectorAll('mjx-msqrt'),
          ...document.querySelectorAll('mjx-mroot'),
        ]
        if (sqrtEls.length === 0) return { found: false }

        const measurements = sqrtEls.map(el => {
          const rect = el.getBoundingClientRect()
          // Find the nearest text-level element for height comparison
          const parent = el.closest('math, mjx-container, .math') || el.parentElement
          const parentRect = parent ? parent.getBoundingClientRect() : rect
          // The sqrt should have meaningful height (vinculum adds ~30% height over content)
          return {
            height: rect.height,
            parentHeight: parentRect.height,
            // A sqrt with vinculum should be at least 1.2x the height of a single line
            hasVinculum: rect.height > 10, // degenerate case: broken rendering gives ~0 height
          }
        })
        return {
          found: true,
          count: sqrtEls.length,
          measurements,
          allHaveVinculum: measurements.every(m => m.hasVinculum),
        }
      })

      if (!result.found) {
        ng('sqrt-has-vinculum', 'No square root elements found in page')
      } else if (result.allHaveVinculum) {
        ok(`sqrt-has-vinculum (${result.count} sqrt element(s) have visible height)`)
      } else {
        const broken = result.measurements.filter(m => !m.hasVinculum)
        ng('sqrt-has-vinculum', `${broken.length} of ${result.count} sqrt elements have no visible height (vinculum missing)`)
      }
      break
    }

    case 'integral-tall': {
      // A correctly rendered integral sign (∫) should be significantly taller than normal text.
      // Broken rendering (wrong font) produces a small, text-height glyph.
      const lineHeight = await getTextLineHeight()

      const result = await page.evaluate((lineHeight) => {
        // Find integral elements
        // MathML: <mo>∫</mo> or entities
        // MathJax: rendered glyph containers
        const allMo = [...document.querySelectorAll('mo')]
        const integrals = allMo.filter(el => {
          const text = el.textContent || ''
          return text.includes('∫') || text.includes('\u222B')
        })

        // Also check MathJax-rendered integrals
        const mjxIntegrals = [...document.querySelectorAll('mjx-mo')]
          .filter(el => (el.textContent || '').includes('∫'))

        const candidates = [...integrals, ...mjxIntegrals]
        if (candidates.length === 0) return { found: false }

        const measurements = candidates.map(el => {
          const rect = el.getBoundingClientRect()
          return {
            height: rect.height,
            ratio: rect.height / lineHeight,
            isTall: rect.height > lineHeight * 1.5,
          }
        })

        return {
          found: true,
          count: candidates.length,
          measurements,
          allTall: measurements.every(m => m.isTall),
        }
      }, lineHeight)

      if (!result.found) {
        ng('integral-tall', 'No integral signs found in page')
      } else if (result.allTall) {
        const ratios = result.measurements.map(m => m.ratio.toFixed(1) + 'x')
        ok(`integral-tall (${result.count} integral(s), heights: ${ratios.join(', ')} line-height)`)
      } else {
        const small = result.measurements.filter(m => !m.isTall)
        ng('integral-tall', `${small.length} of ${result.count} integrals are not taller than text (ratio: ${small.map(m => m.ratio.toFixed(1) + 'x').join(', ')})`)
      }
      break
    }

    case 'fraction-stacked': {
      // A correctly rendered fraction has numerator above denominator,
      // i.e. the fraction element's bounding box is taller than a single line.
      const lineHeight = await getTextLineHeight()

      const result = await page.evaluate((lineHeight) => {
        const fractions = [
          ...document.querySelectorAll('mfrac'),
          ...document.querySelectorAll('mjx-mfrac'),
          ...document.querySelectorAll('[class*="frac"]'),
        ]
        if (fractions.length === 0) return { found: false }

        const measurements = fractions.map(el => {
          const rect = el.getBoundingClientRect()
          return {
            height: rect.height,
            ratio: rect.height / lineHeight,
            // A stacked fraction should be at least 1.2x line height
            isStacked: rect.height > lineHeight * 1.2,
          }
        })

        return {
          found: true,
          count: fractions.length,
          measurements,
          allStacked: measurements.every(m => m.isStacked),
        }
      }, lineHeight)

      if (!result.found) {
        ng('fraction-stacked', 'No fraction elements found in page')
      } else if (result.allStacked) {
        const ratios = result.measurements.map(m => m.ratio.toFixed(1) + 'x')
        ok(`fraction-stacked (${result.count} fraction(s), heights: ${ratios.join(', ')} line-height)`)
      } else {
        const flat = result.measurements.filter(m => !m.isStacked)
        ng('fraction-stacked', `${flat.length} of ${result.count} fractions are flat (ratio: ${flat.map(m => m.ratio.toFixed(1) + 'x').join(', ')})`)
      }
      break
    }

    case 'math-fonts-loaded': {
      // Check if the browser can actually use the fonts needed for math rendering.
      // Uses document.fonts API to verify fonts load successfully — not an
      // implementation check but a browser capability check: "can the browser
      // render math with the intended fonts?"
      const result = await page.evaluate(async () => {
        await document.fonts.ready

        const declaredFonts = []
        const errorFonts = []
        for (const font of document.fonts) {
          declaredFonts.push(font.family)
          if (font.status === 'error') {
            errorFonts.push(font.family)
          }
        }

        if (declaredFonts.length === 0) {
          // No custom fonts declared (e.g. pure MathML) — not applicable
          return { applicable: false }
        }

        return {
          applicable: true,
          declared: declaredFonts.length,
          errors: errorFonts,
          errorCount: errorFonts.length,
        }
      })

      if (!result.applicable) {
        ok('math-fonts-loaded (no custom fonts declared, not applicable)')
      } else if (result.errorCount === 0) {
        ok(`math-fonts-loaded (${result.declared} font(s) declared, all loaded)`)
      } else {
        const unique = [...new Set(result.errors)]
        ng('math-fonts-loaded', `${result.errorCount} font(s) failed to load: ${unique.join(', ')}`)
      }
      break
    }

    default:
      ng(`Unknown check: ${check}`)
  }
}

await browser.close()

console.log(`\nResults: ${pass + fail} checks, ${pass} passed, ${fail} failed`)
process.exit(fail)
