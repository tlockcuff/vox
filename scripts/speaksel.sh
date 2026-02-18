#!/usr/bin/env bash
# SpeakSel — Speak selected text using Kokoro TTS via sherpa-onnx
# This script is called by the macOS Quick Action

set -euo pipefail

SPEAKSEL_DIR="${HOME}/.speaksel"
MODEL_DIR="${SPEAKSEL_DIR}/kokoro-en-v0_19"
TTS_BIN="${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts"
TMP_DIR="${TMPDIR:-/tmp}"

# Read config
VOICE="5"  # Default: am_adam
SPEED="1.0"
[[ -f "${SPEAKSEL_DIR}/voice" ]] && VOICE=$(cat "${SPEAKSEL_DIR}/voice" | tr -d '[:space:]')
[[ -f "${SPEAKSEL_DIR}/speed" ]] && SPEED=$(cat "${SPEAKSEL_DIR}/speed" | tr -d '[:space:]')

# Read text from stdin (piped from Quick Action)
TEXT=$(cat)

# Skip if empty
if [[ -z "${TEXT}" ]]; then
    exit 0
fi

# Truncate very long text (sherpa-onnx can handle a lot, but let's be reasonable)
TEXT="${TEXT:0:10000}"

# Generate unique temp filename
OUTFILE="${TMP_DIR}/speaksel-$$.wav"

# Kill any existing speaksel playback
pkill -f "afplay.*speaksel-" 2>/dev/null || true

# Generate speech
"${TTS_BIN}" \
    --kokoro-model="${MODEL_DIR}/model.onnx" \
    --kokoro-voices="${MODEL_DIR}/voices.bin" \
    --kokoro-tokens="${MODEL_DIR}/tokens.txt" \
    --kokoro-data-dir="${MODEL_DIR}/espeak-ng-data" \
    --kokoro-lexicon="${MODEL_DIR}/lexicon-us-en.txt" \
    --num-threads=2 \
    --sid="${VOICE}" \
    --speed="${SPEED}" \
    --output-filename="${OUTFILE}" \
    "${TEXT}" >/dev/null 2>&1

# Play audio
if [[ -f "${OUTFILE}" ]]; then
    afplay "${OUTFILE}" &
    PLAY_PID=$!
    # Clean up after playback finishes
    (wait "${PLAY_PID}" 2>/dev/null; rm -f "${OUTFILE}") &
fi
