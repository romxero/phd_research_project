#!/bin/bash
set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/generate}"
PIPER_URL="${PIPER_URL:-http://localhost:5000/synthesize}"
MODEL="${MODEL:-gemma4:e4b}"
WAV_FILE="${WAV_FILE:-test.wav}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse Ollama JSON lines and build the Piper payload." >&2
  exit 1
fi

play_wav() {
  local f="$1"
  if command -v pw-play >/dev/null 2>&1; then
    pw-play "$f"
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$f"
  elif command -v aplay >/dev/null 2>&1; then
    aplay "$f"
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$f"
  elif command -v mpv >/dev/null 2>&1; then
    mpv --no-video --really-quiet "$f"
  else
    echo "No audio player found (tried pw-play, paplay, aplay, ffplay, mpv)."
    echo "WAV saved to $f"
  fi
}

while true; do
  read -r -p "Enter the prompt: " prompt || break
  [[ -z "$prompt" ]] && continue

  echo "Generating..."

cat << EOF > /tmp/piper_payload.json
you are an assistant that is helping the user with their question.
do not output in markdown format.
do not output in code blocks.
do not output in json format.
do not output in yaml format.
do not output in xml format.
do not output in html format.
do not output in any other format.
only output the answer to the question.
only use standard text. No emojis, no exclamation marks, quotes, special characters, etc.
Periods and commas are allowed for sentences.

the question is: $prompt

EOF

  # Ollama streams one JSON object per line. Concatenate each .response chunk.
  MY_RESPONSE=$(
    jq -n --arg model "$MODEL" --arg prompt "$(cat /tmp/piper_payload.json)" \
      '{model: $model, prompt: $prompt, stream: true}' \
    | curl -sS -N "$OLLAMA_URL" -H 'Content-Type: application/json' -d @- \
    | jq -j -r '.response // empty'
  )

  echo
  echo "=== Response ==="
  printf '%s\n' "$MY_RESPONSE"
  echo "================"
  echo "Synthesizing with Piper..."

  jq -n --arg text "$MY_RESPONSE" '{text: $text}' \
    | curl -sS -X POST -H 'Content-Type: application/json' \
        -d @- -o "$WAV_FILE" "$PIPER_URL"

  echo "Playing $WAV_FILE"
  play_wav "$WAV_FILE"
done
