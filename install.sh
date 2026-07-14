#!/usr/bin/env bash
#
# install.sh: install the sketchloop skill into an agent's skills directory.
#
# Copies the runtime files (SKILL.md, render.sh, LICENSE, reference/, assets/, examples/), not the
# dev files (CLAUDE.md, test.sh), then checks the two render dependencies and verifies the
# installed copy with a tiny end-to-end render.
#
# Detect-and-instruct only: if d2 or resvg is missing it prints the install command and
# leaves the installing to you.
#
# Usage:
#   install.sh                 # -> ~/.claude/skills/sketchloop (Claude Code, personal)
#   install.sh <dir>           # -> e.g. .claude/skills/sketchloop, ~/.agents/skills/sketchloop
#   install.sh --force [dir]   # overwrite an existing install

set -euo pipefail

die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }

SRC="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

FORCE=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) die "unknown flag: $arg (usage: install.sh [--force] [dest-dir])" ;;
    *) DEST="$arg" ;;
  esac
done
DEST="${DEST:-$HOME/.claude/skills/sketchloop}"

[ -f "$SRC/SKILL.md" ] || die "SKILL.md not found next to install.sh. Run me from a sketchloop checkout"

if [ -e "$DEST" ]; then
  [ "$FORCE" -eq 1 ] || die "$DEST already exists. Re-run with --force to overwrite"
  rm -rf "$DEST"
fi

mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$SRC/render.sh" "$SRC/LICENSE" "$DEST/"
cp -R "$SRC/reference" "$SRC/assets" "$SRC/examples" "$DEST/"
printf 'install.sh: installed -> %s\n' "$DEST"

# --- dependency check: detect and instruct, never auto-install ---
missing=0
command -v d2 >/dev/null 2>&1 || { missing=1
  printf 'install.sh: missing d2    -> brew install d2    (or: curl -fsSL https://d2lang.com/install.sh | sh -)\n'; }
command -v resvg >/dev/null 2>&1 || { missing=1
  printf 'install.sh: missing resvg -> brew install resvg (or: cargo install resvg)\n'; }
if [ "$missing" -eq 1 ]; then
  printf 'install.sh: skill installed, but rendering needs the tool(s) above. Install them, then re-run me with --force to verify.\n'
  exit 0
fi

# --- verify the installed copy end-to-end with a tiny render ---
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf 'a -> b: works\n' > "$TMP/check.d2"
bash "$DEST/render.sh" "$TMP/check.d2" "$TMP/check.png" >/dev/null 2>"$TMP/err" \
  || { cat "$TMP/err" >&2; die "verification render failed"; }
[ -s "$TMP/check.png" ] || die "verification render produced an empty PNG"
printf 'install.sh: verified: d2, resvg, and the bundled font all render.\n'
printf 'install.sh: done. Restart your agent once, then ask it to "draw a hand-drawn diagram".\n'
