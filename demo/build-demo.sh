#!/usr/bin/env bash
# build-demo.sh: assemble the README demo from the vhs recording + real renders.
#
# Inputs (in build/): term.mp4 (vhs demo.tape), sketchloop-works.png (the meta
#   diagram shown in the GIF), jwt-auth-v1.png + jwt-auth-v2.png (the before/after pair).
# Outputs: loop-demo.gif, before-after.png (next to this script).
#
# Rebuild everything from scratch:
#   bash ../render.sh how-sketchloop-works.d2 build/sketchloop-works.png
#   bash ../render.sh jwt-auth-v1.d2 build/jwt-auth-v1.png
#   bash ../render.sh jwt-auth-v2.d2 build/jwt-auth-v2.png
#   vhs demo.tape
#   bash build-demo.sh

set -euo pipefail
cd "$(dirname "$0")"
FONT=../assets/Excalifont-Regular.ttf
B=build

TERM_SECS=7.5     # trim of term.mp4 (content ends ~6s, then holds the final message)
RESULT_SECS=7     # result card: quick zoom onto the sketch, then hold
END_SECS=2.5

meta_b64=$(base64 -i $B/sketchloop-works.png)
v1_b64=$(base64 -i $B/jwt-auth-v1.png)
v2_b64=$(base64 -i $B/jwt-auth-v2.png)

# --- result card: the delivered PNG full-frame (1270x2304 -> 358x650) ---
cat > $B/card-result.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="760">
  <rect width="1000" height="760" fill="#fafafa"/>
  <text x="500" y="52" text-anchor="middle" font-family="Excalifont" font-size="31" fill="#1c1c2e">sketchloop.png: how sketchloop works, drawn by sketchloop</text>
  <image x="321" y="80" width="358" height="650" href="data:image/png;base64,$meta_b64"/>
</svg>
EOF
# rendered at 2x so the zoompan below has pixels to zoom into
resvg --skip-system-fonts --use-font-file $FONT --zoom 2 $B/card-result.svg $B/card-result.png

# --- end card ---
cat > $B/card-end.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="760">
  <rect width="1000" height="760" fill="#fafafa"/>
  <text x="500" y="345" text-anchor="middle" font-family="Excalifont" font-size="72" fill="#2f54c7">sketchloop</text>
  <text x="500" y="415" text-anchor="middle" font-family="Excalifont" font-size="31" fill="#1c1c2e">hand-drawn diagrams, rendered offline, checked by the agent</text>
  <text x="500" y="470" text-anchor="middle" font-family="Excalifont" font-size="23" fill="#8a8a96">github.com/alexander-posztos/sketchloop</text>
</svg>
EOF
resvg --skip-system-fonts --use-font-file $FONT $B/card-end.svg $B/card-end.png

# --- assemble: terminal session -> result card (zoom-in) -> end card, 0.5s crossfades ---
# xfade offsets: first at TERM_SECS - 0.5; second at (TERM_SECS + RESULT_SECS - 0.5) - 0.5.
# Result card: zoompan on the 2x render, 1.0 -> 1.25 over ~0.8s, centered on the sketch
# (input coords 1000,810 = 2x of the diagram center at 500,405), then hold.
ffmpeg -y -v error \
  -t $TERM_SECS -i $B/term.mp4 \
  -loop 1 -t $RESULT_SECS -i $B/card-result.png \
  -loop 1 -t $END_SECS -i $B/card-end.png \
  -filter_complex "\
    [0:v]fps=25,scale=1000:760,format=yuv420p,settb=AVTB[v0]; \
    [1:v]zoompan=z='min(1+0.0125*in,1.25)':x='max(0,min(iw-iw/zoom,1000-(iw/zoom)/2))':y='max(0,min(ih-ih/zoom,810-(ih/zoom)/2))':d=1:s=1000x760:fps=25,format=yuv420p,settb=AVTB[v1]; \
    [2:v]fps=25,scale=1000:760,format=yuv420p,settb=AVTB[v2]; \
    [v0][v1]xfade=transition=fade:duration=0.5:offset=7.0[x1]; \
    [x1][v2]xfade=transition=fade:duration=0.5:offset=13.5[v]" \
  -map "[v]" -c:v libx264 -preset slow -crf 23 $B/master.mp4



# --- GIF (palette pass keeps it small and crisp) ---
ffmpeg -y -v error -i $B/master.mp4 -filter_complex "\
  [0:v]fps=12,split[a][b]; \
  [a]palettegen=stats_mode=diff[p]; \
  [b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  loop-demo.gif

# --- before/after still (for the self-correction section of the README) ---
# v1 strip: 7668x640 -> 620x52; v2: 1524x2018 -> 400x530
cat > $B/before-after.svg <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="820">
  <rect width="1400" height="820" fill="#ffffff"/>
  <text x="700" y="72" text-anchor="middle" font-family="Excalifont" font-size="44" fill="#1c1c2e">Before / After: one self-correction pass</text>
  <line x1="700" y1="130" x2="700" y2="780" stroke="#d8d8de" stroke-width="2"/>

  <text x="350" y="175" text-anchor="middle" font-family="Excalifont" font-size="36" fill="#c0392b">Before</text>
  <rect x="38" y="368" width="624" height="56" fill="none" stroke="#e4e4ea" stroke-width="1"/>
  <image x="40" y="370" width="620" height="52" href="data:image/png;base64,$v1_b64"/>
  <text x="350" y="480" text-anchor="middle" font-family="Excalifont" font-size="26" fill="#1c1c2e">9-box chain, direction: right</text>
  <text x="350" y="520" text-anchor="middle" font-family="Excalifont" font-size="24" fill="#c0392b">7668 x 640 px, aspect 11.98:1, render.sh WARN</text>

  <text x="1050" y="175" text-anchor="middle" font-family="Excalifont" font-size="36" fill="#27ae60">After</text>
  <rect x="848" y="208" width="404" height="534" fill="none" stroke="#e4e4ea" stroke-width="1"/>
  <image x="850" y="210" width="400" height="530" href="data:image/png;base64,$v2_b64"/>
  <text x="1050" y="785" text-anchor="middle" font-family="Excalifont" font-size="24" fill="#1c1c2e">2 containers, direction: down, aspect 1.32:1, clean</text>
</svg>
EOF
resvg --skip-system-fonts --use-font-file $FONT $B/before-after.svg before-after.png

ls -l loop-demo.gif before-after.png
