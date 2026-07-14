#!/usr/bin/env bash
#
# render.sh: render a D2 diagram to a hand-drawn-style PNG, browser-free.
#
# Pipeline (no Chromium, no Node, no network):
#   1. d2 --sketch in.d2 in.svg        rough.js sketch shapes + D2's embedded hand font
#   2. re-point the sketch-font CSS ->  the bundled Excalifont family (on a throwaway copy)
#   3. resvg --use-font-file ...        rasterize with that TTF -> PNG
#
# Why step 2: D2 names its sketch faces "d2-<hash>-font-<face>" and embeds them as base64
# WOFF via @font-face. SVG rasterizers (resvg, rsvg-convert) ignore @font-face, so a plain
# rasterization renders hand-drawn *shapes* but the *text* falls back to a system sans. We
# rewrite the text elements' font-family to a real TTF family we ship and hand resvg that
# file, so strokes AND letters are hand-drawn with no host-font dependency. Faces include
# hyphenated names (e.g. font-mono-bold, for bold tokens in code blocks), hence the [a-z-]
# class. Miss one and those glyphs render blank.
#
# The delivered .svg is left untouched (it embeds D2's own sketch font, so it renders
# hand-drawn in any browser). The rewrite happens on a throwaway copy that only feeds resvg.
#
# Background: D2 bakes an opaque white rect into the SVG. For any non-white background we drop
# that rect on the throwaway copy so resvg's canvas (a color, or transparency) shows through.
#
# Usage:
#   render.sh <diagram.d2> [output.png]
#
# Output: writes <diagram>.svg and <diagram>.png next to the input (or beside the given
# output path), and prints the PNG path to stdout.
#
# Env overrides:
#   D2_SKETCH_FONT          path to a .ttf/.otf hand font (default: bundled Excalifont)
#   D2_SKETCH_FONT_FAMILY   that font's internal family name (default: Excalifont)
#   D2_SKETCH_ZOOM          resvg zoom factor / resolution multiplier (default: 2)
#   D2_SKETCH_BG            PNG background: a color, or "transparent" for alpha (default: white)
#   D2_LAYOUT               layout engine, read natively by d2: "dagre" (default) or "elk"
#   D2_SKETCH_LAYOUT_FLAGS  extra layout flags forwarded verbatim to d2, e.g.
#                           "--dagre-nodesep 30" or "--elk-nodeNodeBetweenLayers 20".
#                           (engine-specific; the flag must match the active D2_LAYOUT.)
#   D2_SKETCH_OPEN          if truthy (1/true/yes/on), open the finished PNG in the OS
#                           default viewer (open | xdg-open | wslview | cmd.exe start).
#                           Opt-in, default off; fail-soft, never breaks the render.
#
# After rendering, prints the output size and aspect ratio to stderr, and a WARN when the
# ratio exceeds ~3:1 (a likely "thin strip": wrap a long chain or split). Non-fatal: the
# PNG is always written. Some diagrams (sequence, wide ER) are legitimately wide. Use
# judgment, but treat the WARN as a strong hint to reshape the layout.

set -euo pipefail

die() { printf 'render.sh: %s\n' "$1" >&2; exit 1; }

# --- locate this script's real directory (following symlinks), so the bundled font resolves
#     regardless of CWD or a symlinked invocation on PATH ---
src="${BASH_SOURCE[0]:-$0}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in
    /*) ;;
    *) src="$dir/$src" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"

FONT_FILE="${D2_SKETCH_FONT:-$SCRIPT_DIR/assets/Excalifont-Regular.ttf}"
FONT_FAMILY="${D2_SKETCH_FONT_FAMILY:-Excalifont}"
ZOOM="${D2_SKETCH_ZOOM:-2}"
BG="${D2_SKETCH_BG:-white}"

# Aspect ratio (longer side / shorter side) above which we flag a likely thin strip.
MAX_ASPECT=3

# Extra layout flags for d2, word-split into argv (no globbing). Safe-empty under set -u.
IFS=' ' read -r -a LAYOUT_FLAGS <<< "${D2_SKETCH_LAYOUT_FLAGS:-}"

# FONT_FAMILY is interpolated into a sed replacement; keep it to characters safe there.
case "$FONT_FAMILY" in
  ""|*[!A-Za-z0-9._\ -]*) die "D2_SKETCH_FONT_FAMILY may use only letters, digits, space, '.', '_', '-': '$FONT_FAMILY'" ;;
esac

# --- args ---
[ $# -ge 1 ] || die "usage: render.sh <diagram.d2> [output.png]"
IN="$1"
[ -f "$IN" ] || die "input not found: $IN"

if [ $# -ge 2 ]; then
  PNG="$2"
  case "$PNG" in
    *.png) ;;
    *) die "output path must end in .png: $PNG" ;;
  esac
else
  PNG="${IN%.d2}.png"
fi
SVG="${PNG%.png}.svg"

# --- dependency checks (clear, actionable) ---
command -v d2    >/dev/null 2>&1 || die "'d2' not found. Install: https://d2lang.com (brew install d2 | curl -fsSL https://d2lang.com/install.sh | sh -)"
command -v resvg >/dev/null 2>&1 || die "'resvg' not found. Install: https://github.com/linebender/resvg/releases (brew install resvg | cargo install resvg)"
[ -f "$FONT_FILE" ] || die "font not found: $FONT_FILE"

# --- 1. D2 sketch -> SVG (this SVG is a deliverable; self-contained, hand-drawn in browsers).
#        Clear any stale SVG first: d2 exits 0 without writing on empty/content-free input. ---
rm -f "$SVG"
d2 --sketch ${LAYOUT_FLAGS[@]+"${LAYOUT_FLAGS[@]}"} "$IN" "$SVG" >&2
[ -s "$SVG" ] || die "d2 produced no SVG. Is '$IN' empty or content-free?"
chmod +r "$SVG"   # d2 writes it 0600; the SVG is a deliverable, make it readable like the PNG

# --- 2. on a throwaway copy: re-point the sketch font to the bundled family; for a non-white
#        background, also drop D2's opaque background rect so the canvas shows through ---
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
sed -E "s/\"d2-[0-9]+-font-[a-z-]+\"/\"$FONT_FAMILY\"/g" "$SVG" > "$TMP_DIR/render.svg"
if [ "$BG" != white ]; then
  sed -E 's#<rect[^>]*class="[^"]*fill-N7[^"]*"[^>]*/>##' "$TMP_DIR/render.svg" > "$TMP_DIR/clean.svg"
  mv "$TMP_DIR/clean.svg" "$TMP_DIR/render.svg"
fi

# --- 3. resvg rasterize with the bundled TTF (transparent => no --background) ---
RESVG_ARGS=(--skip-system-fonts --use-font-file "$FONT_FILE" --zoom "$ZOOM")
if [ "$BG" != transparent ] && [ "$BG" != none ]; then
  RESVG_ARGS+=(--background "$BG")
fi
# resvg warns that it skips @font-face on every render; here that's the expected design
# (step 2 exists because of it), so drop that one line from stderr. Real errors pass through.
if ! resvg "${RESVG_ARGS[@]}" "$TMP_DIR/render.svg" "$PNG" 2>"$TMP_DIR/resvg.err"; then
  cat "$TMP_DIR/resvg.err" >&2
  die "resvg failed"
fi
grep -v 'The @font-face rule is not supported' "$TMP_DIR/resvg.err" >&2 || true

# --- aspect-ratio gate: report size + ratio, WARN on a likely thin strip (non-fatal) ---
#     Ratio is read from the SVG viewBox (zoom-invariant); px size = viewBox * ZOOM.
VIEWBOX="$(grep -oE 'viewBox="[0-9. ]+"' "$SVG" | head -1)"
awk -v vb="$VIEWBOX" -v zoom="$ZOOM" -v ceil="$MAX_ASPECT" 'BEGIN {
  gsub(/viewBox="|"/, "", vb); split(vb, a, " ")
  w = a[3]; h = a[4]
  if (w <= 0 || h <= 0) exit
  r = (w > h) ? w / h : h / w
  printf("render.sh: %d x %d px  (aspect %.2f:1)\n", w * zoom, h * zoom, r) > "/dev/stderr"
  if (r > ceil)
    printf("render.sh: WARN aspect %.2f:1 exceeds %d:1, likely a thin strip. Merge stages to <=5 per axis, grid-columns a set of peers, or split a long sequence into multiple diagrams; flipping direction alone will not fix it.\n", r, ceil) > "/dev/stderr"
}'

# --- optional auto-open (opt-in via D2_SKETCH_OPEN; fail-soft, never breaks the render) ---
#     Backgrounded with output suppressed, so a missing display or slow viewer can't stall
#     or fail the script. Default off. The agent only enables it on the final deliver render.
case "${D2_SKETCH_OPEN:-}" in
  1|true|yes|on|TRUE|YES|ON|True|Yes|On)
    opener=""
    for cmd in open xdg-open wslview; do
      if command -v "$cmd" >/dev/null 2>&1; then opener="$cmd"; break; fi
    done
    if [ -n "$opener" ]; then
      "$opener" "$PNG" >/dev/null 2>&1 &
      printf 'render.sh: opened %s in the default viewer (%s)\n' "$PNG" "$opener" >&2
    elif command -v cmd.exe >/dev/null 2>&1; then
      cmd.exe /c start "" "$PNG" >/dev/null 2>&1 &   # Git Bash / WSL without wslview
      printf 'render.sh: opened %s via cmd.exe start\n' "$PNG" >&2
    else
      printf 'render.sh: D2_SKETCH_OPEN set but no opener found (tried open, xdg-open, wslview, cmd.exe), skipping\n' >&2
    fi
    ;;
esac

# --- machine-readable result on stdout; everything else went to stderr ---
printf '%s\n' "$PNG"
