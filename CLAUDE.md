# sketchloop

A model- and harness-agnostic **agent skill**: an LLM authors a [D2](https://d2lang.com)
diagram as text, and the skill renders it to a **hand-drawn-style image** (PNG/SVG)
**without a browser**: no Chromium, no Node, no server. The agent then *looks at the
rendered PNG* and fixes its own diagram in a short loop.

**Goal:** the easiest, most portable way to make an agent "draw me a hand-drawn diagram"
and get back an actual image: install once, runs offline, works in any local-shell agent
harness (Claude Code, Cursor, Copilot CLI, …).

> **Status: built and verified.** The render path, font pipeline, and self-correct loop are
> implemented and confirmed empirically (see below). These are accurate dev notes for the
> repo, not a plan.

## Positioning (the gap it fills)

Existing hand-drawn-diagram agent tools either pull in a headless browser (Excalidraw /
tldraw via Playwright, Mermaid via Puppeteer) or are MCP servers needing per-client config.
The browser-free D2 tools that exist (`h0rv/d2-mcp`, `i2y/d2mcp`) are MCP servers, not
portable *skills*, and don't bake in the self-correction loop. **sketchloop is the only
browser-free, single-binary, fully-local D2 hand-drawn diagram skill that works in any
local-shell agent and checks its own output.**

## Core pipeline (implemented in `render.sh`)

1. Agent writes a `.d2` file, a terse text DSL with **automatic layout** (no coordinate math).
2. `d2 --sketch diagram.d2 diagram.svg` → hand-drawn SVG (rough.js shapes), browser-free.
   This SVG is a **deliverable**: it embeds D2's own sketch font as base64 WOFF, so it
   renders hand-drawn in any browser. It is left untouched.
3. **Font rewrite (on a throwaway copy):** `sed -E 's/"d2-[0-9]+-font-[a-z-]+"/"Excalifont"/g'`.
   D2 names its sketch faces `d2-<hash>-font-<face>` (per-document hash). The **quoted**
   token is the `.text*` element-styling rule (the *usage*). The regex re-points it to the
   bundled family; the matching unquoted token lives in the `@font-face` block, which resvg
   ignores anyway. Faces seen: `-regular` / `-bold` / `-italic`, plus **hyphenated** ones like
   `-mono-bold` (bold tokens in code blocks). The `[a-z-]+` class is required to catch those,
   or those glyphs render blank. All map to the one bundled family.
4. **Background (throwaway copy):** D2 bakes an opaque white `fill-N7` rect into the SVG. For
   any non-white `D2_SKETCH_BG`, that rect is stripped so resvg's canvas shows through.
5. `resvg --skip-system-fonts --use-font-file assets/Excalifont-Regular.ttf --zoom 2
   --background white tmp.svg diagram.png` → PNG (transparent ⇒ omit `--background`).
   Browser-free, ~300 ms end-to-end.
6. Agent **Reads the PNG**, checks for overlaps / clipping / wrong topology / unreadable
   labels, edits the `.d2`, re-renders. Bounded loop (~2-3 passes).
7. Deliverables: the PNG, the SVG, and the editable `.d2` source.

## Key decisions / findings (settled, verified firsthand)

- **Rasterizer is `resvg`, not `rsvg-convert`.** resvg ships one static binary per OS;
  rsvg-convert on Windows is a stale mess. Both work on the Mac/Linux path, but resvg is the
  portable single-binary choice.
- **The bundled font is swapped in via a font-family rewrite, NOT `--font-regular`.** Verified:
  D2 embeds its sketch font as a base64 WOFF `@font-face`, and **both resvg and rsvg-convert
  ignore `@font-face`**, so a naive rasterization renders hand-drawn *shapes* with plain-sans
  *text*, and D2's `--font-regular` flag does nothing on this path. The working recipe is to
  rewrite the SVG's `font-family` references to a real bundled TTF family and pass that file
  to `resvg --use-font-file`. (This overturns an earlier docs-read that claimed "D2 sketch
  text is already hand-drawn": true in a browser, false on the rasterization path.)
- **Bundled font: Excalifont** (Excalidraw's own OFL hand font; the exact "hand-drawn like
  Excalidraw" aesthetic, tuned for legibility). Upstream ships woff2 only, so it's converted
  woff2→TTF **once at bundle time** (`fonttools ttLib.woff2 decompress`, needs `brotli`);
  the repo ships the static TTF + its OFL text (extracted from the font's name table).
  Internal family name is `Excalifont`. Swappable via `D2_SKETCH_FONT` + `D2_SKETCH_FONT_FAMILY`.
- **Never use D2's native PNG/PDF export**: it lazily downloads a ~140 MB headless Chromium.
  Rasterize the SVG with resvg instead. This is the whole point of the project.
- **D2 over Excalidraw / Mermaid / tldraw**: single Go binary, terse for LLMs, auto-layout
  (LLMs are bad at coordinates), genuine rough.js sketch. Trade-off: output is `.d2` / `.svg`
  / `.png`, not the editable `.excalidraw` format.
- **Harness-agnostic** = a plain `SKILL.md` (open Agent Skills standard) + shell commands.
  `render.sh` self-locates via `dirname "${BASH_SOURCE[0]}"`, **no `$CLAUDE_SKILL_DIR`**.
  Reach is **any local-shell agent harness** (Claude Code, Cursor, Copilot CLI), **not**
  claude.ai / the API sandbox (no binaries there).

## Runtime dependencies

- `d2`: single Go binary (`brew install d2`, install.sh, or `go install`). Verified on 0.7.1.
- `resvg`: single Rust binary (`brew install resvg`, `cargo install resvg`, or a release
  binary). Verified on 0.47.0.
- Bundled OFL hand font (Excalifont). **No** Node, **no** Chromium, **no** network at runtime.

## Layout (as built)

- `SKILL.md`: the skill: authoring guidance (shape rules, aspect targets), the
  render/self-correct loop, the `sketches/` output convention (deliverables go to
  `./sketches/` under the user's CWD; never /tmp, never touch the user's `.gitignore`),
  and final delivery via `D2_SKETCH_OPEN=1` (opens the PNG in the OS viewer).
- `render.sh`: self-locating wrapper (`d2 --sketch` → font rewrite → `resvg` → prints PNG
  path; reports size + aspect ratio on stderr with a WARN past 3:1). Env knobs:
  `D2_SKETCH_ZOOM`, `D2_SKETCH_BG`, `D2_SKETCH_FONT`(`_FAMILY`), `D2_SKETCH_LAYOUT_FLAGS`,
  `D2_SKETCH_OPEN`, plus d2's native `D2_LAYOUT`.
- `reference/d2-cheatsheet.md`: D2 authoring quick-reference (verified against 0.7.1).
- `assets/Excalifont-Regular.ttf` + `Excalifont-OFL.txt`: the bundled hand font + its license.
- `examples/`: six worked examples, each `.d2` + `.svg` + `.png`: `how-sketchloop-works`,
  `render-loop`, `web-architecture`, `service-catalog`, `checkout-1-payment` +
  `checkout-2-fulfillment` (the split-diagram pattern).
- `install.sh`: copies the runtime files (not the dev files), dep-checks d2/resvg
  (detect-and-instruct only), verifies with a real render; `--force` overwrites.
- `test.sh`: dev-only regression suite (render, aspect gate, font-rewrite canaries).
  Keep it green.
- `demo/`: README demo pipeline: `replay.sh` (fully scripted session) → `demo.tape` (vhs)
  → `build-demo.sh` (assembles `loop-demo.gif` + `before-after.png`); `demo/build/` is
  gitignored intermediates.
- `README.md` (public, leads with offline + hand-drawn + self-correcting), `LICENSE` (MIT).

## Conventions

- Offline-first; zero runtime deps beyond the two CLIs + the bundled font.
- No emoji in diagrams (they don't render in the hand font). No `icon:` URLs (need network).
- Standalone **public** repo: self-contained, MIT (font separately under SIL OFL 1.1).
</content>
