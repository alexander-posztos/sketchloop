#!/usr/bin/env bash
#
# test.sh: offline smoke test for render.sh. No network; needs only d2 + resvg (the same
# two binaries render.sh needs). Renders a few inline fixtures and asserts the contract:
# PNG non-empty, aspect-ratio gate in band / WARNs on a strip, D2_SKETCH_LAYOUT_FLAGS
# actually reaches d2, a bad layout flag fails loudly, and the font-rewrite canary (d2's
# internal sketch-font naming still matches the rewrite regex). Run: bash test.sh
#
# NOT set -e: several checks deliberately exercise the failure path.
set -uo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
R="$DIR/render.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
no() { printf 'FAIL - %s\n' "$1"; fail=$((fail+1)); }

# Fixtures: a balanced grid, a long-chain strip, a fan-out (for the spacing-flag check).
printf 'grid-columns: 3\na;b;c;d;e;f;g;h;i\n'            > "$TMP/block.d2"
printf 'direction: right\na -> b -> c -> d -> e -> f -> g\n' > "$TMP/strip.d2"
printf 'r -> a\nr -> b\nr -> c\nr -> d\n'                > "$TMP/fan.d2"

# Run render.sh, capturing only its stderr (the size/aspect/WARN line lives there).
run()   { bash "$R" "$1" "$2" 2>&1 >/dev/null; }
ratio() { grep -oE 'aspect [0-9.]+' | grep -oE '[0-9.]+' | head -1; }  # stdin -> bare ratio
dims()  { grep -oE '[0-9]+ x [0-9]+ px'; }                    # stdin -> "W x H px"

# 1. balanced fixture: PNG non-empty, aspect in band, no WARN.
err="$(run "$TMP/block.d2" "$TMP/block.png")"
[ -s "$TMP/block.png" ] && ok "block: PNG non-empty" || no "block: PNG empty/missing"
r="$(ratio <<<"$err")"
awk "BEGIN{exit !($r<=3)}" && ok "block: aspect $r:1 in band (<=3)" || no "block: aspect $r:1 out of band"
grep -q WARN <<<"$err" && no "block: unexpected strip WARN" || ok "block: no strip WARN"

# 2. strip fixture: the gate must WARN.
err="$(run "$TMP/strip.d2" "$TMP/strip.png")"
grep -q WARN <<<"$err" && ok "strip: gate WARNs ($(ratio <<<"$err"):1)" || no "strip: gate should WARN"

# 3. D2_SKETCH_LAYOUT_FLAGS reaches d2: wider node spacing changes the dimensions.
a="$(run "$TMP/fan.d2" "$TMP/fa.png" | dims)"
b="$(D2_SKETCH_LAYOUT_FLAGS='--dagre-nodesep 150' bash "$R" "$TMP/fan.d2" "$TMP/fb.png" 2>&1 >/dev/null | dims)"
[ -n "$a" ] && [ "$a" != "$b" ] && ok "LAYOUT_FLAGS changes dims ($a -> $b)" || no "LAYOUT_FLAGS no effect ($a vs $b)"

# 4. a bad layout flag must fail (non-zero exit), not render silently.
if D2_SKETCH_LAYOUT_FLAGS='--bogus-flag' bash "$R" "$TMP/fan.d2" "$TMP/bad.png" >/dev/null 2>&1; then
  no "bad flag should exit non-zero"
else
  ok "bad flag exits non-zero"
fi

# 5. font-rewrite canary: the "hand-drawn text" promise hangs on render.sh's regex matching
#    d2's internal (undocumented) "d2-<hash>-font-<face>" names. If a d2 upgrade renames
#    them, text silently falls back to sans with no error anywhere, so fail loudly here.
svg="$TMP/block.svg"   # written next to block.png by check 1
grep -qF 'd2-[0-9]+-font-[a-z-]+' "$R" \
  && ok "font: render.sh still uses the rewrite pattern this canary mirrors" \
  || no "font: render.sh's rewrite pattern changed. Update this canary to match"
grep -qE '"d2-[0-9]+-font-[a-z-]+"' "$svg" \
  && ok "font: SVG uses the d2-<hash>-font-<face> naming the rewrite expects" \
  || no "font: d2's sketch-font naming changed: the rewrite regex no longer matches"
rewritten="$(sed -E 's/"d2-[0-9]+-font-[a-z-]+"/"Excalifont"/g' "$svg")"
grep -qE '"d2-[0-9]+-font-' <<<"$rewritten" \
  && no "font: a face name escaped the rewrite (quoted d2-*-font-* token survived)" \
  || ok "font: rewrite catches every quoted font token"
grep -q '"Excalifont"' <<<"$rewritten" \
  && ok "font: rewrite produced \"Excalifont\" references" \
  || no "font: no \"Excalifont\" reference after rewrite"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
