#!/usr/bin/env bash
# replay.sh: simulate a Claude Code session invoking the sketchloop skill.
# Played inside a vhs recording; every printed line is scripted, the render
# numbers shown are the real output of render.sh on demo/how-sketchloop-works.d2.

set -u

PROMPT='/sketchloop how does sketchloop work?'

# colors
DIM=$'\033[90m'
GREEN=$'\033[38;5;114m'
ORANGE=$'\033[38;5;215m'
BOLD=$'\033[1m'
R=$'\033[0m'

BOXW=72   # inner width of the input box

type_in_box() {
  local text="$1" prefix="" line pad
  # draw the empty input box (3 lines), leave cursor on the line below it
  printf '╭'; printf '─%.0s' $(seq 1 $((BOXW + 2))); printf '╮\n'
  printf '│ %-*s │\n' "$BOXW" '> █'
  printf '╰'; printf '─%.0s' $(seq 1 $((BOXW + 2))); printf '╯\n'
  local i
  for ((i = 1; i <= ${#text}; i++)); do
    prefix="${text:0:i}"
    line="> ${prefix}█"
    pad=$((BOXW - ${#line}))
    printf '\033[2A\r│ %s%*s │\033[2B\r' "$line" "$pad" ''
    sleep 0.035
  done
  sleep 0.9
}

spinner() {
  local label="$1" secs="$2" glyphs='✢✳✶✻✽✻✶✳' i=0 n
  n=$(awk -v s="$secs" 'BEGIN { print int(s / 0.12) }')
  while ((i < n)); do
    printf '\r%s%s%s %s… %s(esc to interrupt)%s' "$ORANGE" "${glyphs:i % 8:1}" "$R" "$label" "$DIM" "$R"
    sleep 0.12
    ((i++))
  done
  printf '\r\033[K'
}

tool() {  # tool call line: ⏺ Name(args)
  printf '%s⏺%s %s%s%s(%s)\n' "$GREEN" "$R" "$BOLD" "$1" "$R" "$2"
  sleep 0.2
}

res() {  # result line(s): ⎿ text
  printf '  %s⎿  %s%s\n' "$DIM" "$1" "$R"
}

clear
printf '\033[?25l'   # hide the real terminal cursor; the fake block in the box plays cursor
sleep 0.6

type_in_box "$PROMPT"

# submitted prompt becomes a transcript line
clear
printf '\033[?25l'
printf '%s> %s%s\n\n' "$DIM" "$PROMPT" "$R"

spinner 'Sketching' 0.7

tool 'Write' 'sketches/sketchloop.d2'
res 'Wrote 33 lines to sketches/sketchloop.d2'
printf '\n'
sleep 0.35

tool 'Bash' 'bash ~/.claude/skills/sketchloop/render.sh sketches/sketchloop.d2'
sleep 0.4
res 'render.sh: 1270 x 2304 px  (aspect 1.81:1)'
printf '     %ssketches/sketchloop.png%s\n' "$DIM" "$R"
printf '\n'
sleep 0.35

tool 'Read' 'sketches/sketchloop.png'
res 'Read image (174KB)'
printf '\n'
sleep 0.35

printf '%s⏺%s Looks clean: balanced layout, readable labels, correct flow.\n' "$GREEN" "$R"
printf '  Delivered %ssketches/sketchloop.png%s, plus the .svg and editable .d2 source.\n' "$BOLD" "$R"
# hold the final frame past the end of the recording (no shell prompt / logout)
sleep 15
