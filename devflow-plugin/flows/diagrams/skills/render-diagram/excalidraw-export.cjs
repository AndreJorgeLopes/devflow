#!/usr/bin/env node
/**
 * excalidraw-export.cjs — render a .excalidraw file to PNG (and SVG) with ZERO
 * browser / headless-Chromium / MCP dependency.
 *
 * Pipeline:  .excalidraw JSON
 *              -> excalidraw-to-svg (jsdom + node-canvas for text metrics) -> SVG
 *              -> @resvg/resvg-js (prebuilt Rust N-API rasteriser)          -> PNG
 *
 * Why CommonJS (.cjs): global npm deps are resolved via NODE_PATH, which Node
 * consults for `require()` but NOT for ESM `import`. The devflow CLI invokes this
 * with `NODE_PATH="$(npm root -g)"` so the globally-installed deps resolve.
 *
 * Usage:  node excalidraw-export.cjs <input.excalidraw> [output-basename] [--width N]
 *   - output-basename defaults to the input path minus the .excalidraw extension.
 *   - writes <basename>.svg and <basename>.png next to each other.
 *   - prints the PNG path (last line of stdout) for callers to capture.
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ── arg parsing ──────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
if (args.length === 0 || args[0] === '-h' || args[0] === '--help') {
  console.error('usage: excalidraw-export.cjs <input.excalidraw> [output-basename] [--width N] [--bg COLOR]');
  process.exit(args.length === 0 ? 1 : 0);
}
let width = 1600;
let bgOverride = null;
const positional = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--width') { width = parseInt(args[++i], 10) || width; }
  else if (args[i] === '--bg') { bgOverride = args[++i]; }
  else positional.push(args[i]);
}
const inputPath = path.resolve(positional[0]);
const baseName = path.resolve(positional[1] || positional[0].replace(/\.excalidraw$/i, ''));
const svgPath = baseName + '.svg';
const pngPath = baseName + '.png';

if (!fs.existsSync(inputPath)) {
  console.error(`excalidraw-export: input not found: ${inputPath}`);
  process.exit(1);
}

// ── suppress known non-fatal jsdom resource noise ──────────────────────────────
// excalidraw-to-svg's internal jsdom tries to preload a couple of embedded
// data-URI icon images that have no intrinsic width/height. These surface as
// loud "Could not load img" / "Width and height must be set" jsdomError lines
// on console.error but do NOT affect the rendered shapes/text/arrows. Drop only
// those specific lines; let every other diagnostic through untouched.
const NOISE = [
  'Could not load img',
  'Width and height must be set on the svg element',
];
const origError = console.error.bind(console);
console.error = (...a) => {
  const s = a.map((x) => (x && x.message) ? x.message : String(x)).join(' ');
  if (NOISE.some((n) => s.includes(n))) return;
  origError(...a);
};

// ── deps (resolved via NODE_PATH for global installs) ──────────────────────────
let toSvg = require('excalidraw-to-svg');
if (toSvg && toSvg.default) toSvg = toSvg.default;
const { Resvg } = require('@resvg/resvg-js');

// ── normalize bound text: re-center every container-bound label ─────────────────
// excalidraw-to-svg (via @excalidraw/utils' exportToSvg) renders each text element
// at its LITERAL x/y and lays its lines out across the text element's OWN height —
// it does NOT live-recenter bound text inside its container the way the Excalidraw
// app does. So a hand-authored file whose bound text drifted from its container
// renders the label off-centre; the classic symptom is a multi-line label riding
// against the top edge (verticalAlign "top", or a height that doesn't match the
// line count). This pass recomputes each bound text's box from its container so
// labels center reliably and font-metric-independently: text-anchor=middle handles
// horizontal centering, while an exact line-block height + a centered y handles
// vertical. It is a no-op on diagrams that were already correct.
//
// It only RE-POSITIONS the text; it never grows the container. Growing a box would
// move its edge away from any bound arrow and visually disconnect it, so when a
// label is taller than its box we warn instead of resizing.
function normalizeBoundText(json) {
  const els = Array.isArray(json.elements) ? json.elements : [];
  const byId = new Map(els.map((e) => [e.id, e]));
  const CONTAINERS = new Set(['rectangle', 'ellipse', 'diamond']);
  for (const t of els) {
    if (!t || t.type !== 'text' || !t.containerId) continue;
    const c = byId.get(t.containerId);
    if (!c || !CONTAINERS.has(c.type)) continue;
    const fontSize = t.fontSize || 16;
    const lineHeight = t.lineHeight || 1.25;
    const str = (t.originalText != null ? t.originalText : t.text) || '';
    const lines = String(str).split('\n').length;
    const blockH = lines * fontSize * lineHeight;
    // Horizontal: full-width text box + text-anchor=middle centers font-independently.
    // Vertical: @excalidraw/utils' exportToSvg does NOT vertically center bound text
    // the way the live app does — empirically the glyph block drifts UP by half a
    // line per extra line (≈ fontSize*lineHeight/2 each). The naive
    // `c.y + (c.height - blockH)/2` is therefore wrong by ~blockH/2 (tall labels
    // overflow the top). The y below was reverse-engineered by measuring rendered
    // baselines: box-centre, plus a per-line correction, minus an ascent/optical
    // fudge (~0.45*fontSize). Verified centered across font sizes × line counts.
    t.textAlign = t.textAlign || 'center';
    t.verticalAlign = 'middle';
    t.x = c.x;
    t.width = c.width;
    t.height = blockH;
    t.y = c.y + c.height / 2 + ((lines - 1) * fontSize * lineHeight) / 2 - 0.75 * fontSize + 2;
    if (blockH > c.height + 0.5) {
      origError(
        `excalidraw-export: WARN label "${String(str).replace(/\n/g, ' ').slice(0, 40)}" ` +
        `is ${Math.round(blockH)}px tall but its box (${c.id}) is only ${c.height}px — ` +
        `text will overflow; enlarge the box in the source.`
      );
    }
  }
}

(async () => {
  const json = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  if (!json || !Array.isArray(json.elements)) {
    throw new Error(`not a valid .excalidraw file (missing elements[]): ${inputPath}`);
  }

  // Re-center every container-bound label before rendering (see normalizeBoundText).
  normalizeBoundText(json);

  // Background: explicit --bg wins, else the file's own canvas colour (so dark-mode
  // diagrams render on their dark canvas instead of a forced white sheet), else white.
  const bg = bgOverride
    || (json.appState && json.appState.viewBackgroundColor)
    || 'white';

  // excalidraw-to-svg loads @excalidraw/utils' dist bundle via a CWD-RELATIVE
  // path ("./node_modules/@excalidraw/utils/dist/excalidraw-utils.min.js"). With
  // globally-installed deps that breaks unless cwd contains the matching
  // node_modules. Find a base dir where that relative path exists and chdir to
  // it. (Input/output paths were resolved to absolute above, so chdir is safe.)
  const REL = 'node_modules/@excalidraw/utils/dist/excalidraw-utils.min.js';
  const gm = process.env.EXCAL_NODE_MODULES || '';
  let base = null;
  for (const t of [path.dirname(gm), path.join(gm, 'excalidraw-to-svg')]) {
    if (t && fs.existsSync(path.join(t, REL))) { base = t; break; }
  }
  if (!base) {
    throw new Error('cannot locate @excalidraw/utils dist bundle; reinstall: npm i -g excalidraw-to-svg');
  }
  process.chdir(base);

  // 1) .excalidraw -> SVG (DOM-based, via jsdom)
  const svgEl = await toSvg(json);
  const svg = svgEl.outerHTML
    || (svgEl.documentElement && svgEl.documentElement.outerHTML)
    || String(svgEl);
  fs.writeFileSync(svgPath, svg);

  // 2) SVG -> PNG (resvg, prebuilt; system fonts for any text)
  const resvg = new Resvg(svg, {
    fitTo: { mode: 'width', value: width },
    background: bg,
    font: { loadSystemFonts: true },
  });
  const png = resvg.render().asPng();
  fs.writeFileSync(pngPath, png);

  // machine-readable result: SVG path, then PNG path as the final line
  console.log('SVG ' + path.resolve(svgPath));
  console.log('PNG ' + path.resolve(pngPath));
})().catch((e) => {
  origError('excalidraw-export FAILED: ' + (e && e.message ? e.message : e));
  process.exit(1);
});
