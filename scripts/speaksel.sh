#!/usr/bin/env bash
# SpeakSel — Speak selected text using Kokoro TTS via sherpa-onnx
# If the menu bar app is running, delegates to it. Otherwise plays directly.

set -euo pipefail

SPEAKSEL_DIR="${HOME}/.speaksel"
MODEL_DIR="${SPEAKSEL_DIR}/kokoro-en-v0_19"
TTS_BIN="${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts"
REQUEST_FILE="${SPEAKSEL_DIR}/.request"
WAV_FILE="${SPEAKSEL_DIR}/.current.wav"

export DYLD_LIBRARY_PATH="${SPEAKSEL_DIR}/bin:${DYLD_LIBRARY_PATH:-}"

# Read config
VOICE="5"
SPEED="1.0"
[[ -f "${SPEAKSEL_DIR}/voice" ]] && VOICE=$(cat "${SPEAKSEL_DIR}/voice" | tr -d '[:space:]')
[[ -f "${SPEAKSEL_DIR}/speed" ]] && SPEED=$(cat "${SPEAKSEL_DIR}/speed" | tr -d '[:space:]')

# --- Commands ---
stop_playback() {
    # Signal the menu bar app
    echo "__STOP__" > "${REQUEST_FILE}"
    # Also kill any direct playback
    pkill -f "afplay.*speaksel" 2>/dev/null || true
    pkill -f "afplay.*chunk_" 2>/dev/null || true
}

speak_text() {
    local text="$1"
    [[ -z "${text}" ]] && exit 0
    text="${text:0:10000}"

    # If menu bar app is running, delegate to it
    if pgrep -f "SpeakSel" >/dev/null 2>&1; then
        echo "${text}" > "${REQUEST_FILE}"
        return
    fi

    # Fallback: direct playback (no UI)
    stop_playback

    LENGTH_SCALE=$(awk -v s="${SPEED}" 'BEGIN{printf "%.2f", 1/s}')

    "${TTS_BIN}" \
        --kokoro-model="${MODEL_DIR}/model.onnx" \
        --kokoro-voices="${MODEL_DIR}/voices.bin" \
        --kokoro-tokens="${MODEL_DIR}/tokens.txt" \
        --kokoro-data-dir="${MODEL_DIR}/espeak-ng-data" \
        --num-threads=2 \
        --sid="${VOICE}" \
        --kokoro-length-scale="${LENGTH_SCALE}" \
        --output-filename="${WAV_FILE}" \
        "${text}" >/dev/null 2>&1

    if [[ -f "${WAV_FILE}" ]]; then
        afplay "${WAV_FILE}" &
        (wait $! 2>/dev/null; rm -f "${WAV_FILE}") &
    fi
}

# --- Main ---
case "${1:-speak}" in
    stop)    stop_playback ;;
    speak|*)
        [[ "${1:-}" == "speak" ]] && shift || true
        if [[ $# -gt 0 ]]; then
            speak_text "$*"
        else
            speak_text "$(cat)"
        fi
        ;;
esac
