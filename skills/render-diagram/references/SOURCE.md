# Source & attribution

These Excalidraw authoring references are vendored from the **`ooiyeefei/ccc`** project's
`excalidraw` skill (`skills/excalidraw/references/`), which is MIT licensed.

- Upstream: https://github.com/ooiyeefei/ccc
- License: MIT
- Vendored files: `json-format.md`, `arrows.md`, `colors.md`, `examples.md`, `validation.md`

They are bundled here so devflow's `/devflow:render-diagram` skill can author valid
`.excalidraw` JSON **without depending on the ccc Claude Code plugin being installed**.

Only these reference docs are vendored. devflow renders `.excalidraw` to PNG via its own
pure-node pipeline (`lib/excalidraw-export.cjs`: `excalidraw-to-svg` + `@resvg/resvg-js`),
not ccc's Playwright/browser export — so `references/export.md` is intentionally NOT vendored.
