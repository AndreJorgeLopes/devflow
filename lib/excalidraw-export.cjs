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
  console.error('usage: excalidraw-export.cjs <input.excalidraw> [output-basename] [--width N]');
  process.exit(args.length === 0 ? 1 : 0);
}
let width = 1600;
const positional = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--width') { width = parseInt(args[++i], 10) || width; }
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

(async () => {
  const json = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  if (!json || !Array.isArray(json.elements)) {
    throw new Error(`not a valid .excalidraw file (missing elements[]): ${inputPath}`);
  }

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
    background: 'white',
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
