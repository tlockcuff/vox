#!/usr/bin/env bash
# SpeakSel — Speak selected text using Kokoro TTS via sherpa-onnx
# This script is called by the macOS Quick Action, Raycast, or keyboard shortcut

set -euo pipefail

SPEAKSEL_DIR="${HOME}/.speaksel"
MODEL_DIR="${SPEAKSEL_DIR}/kokoro-en-v0_19"
TTS_BIN="${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts"
TMP_DIR="${TMPDIR:-/tmp}"
PID_FILE="${SPEAKSEL_DIR}/.playback.pid"
WAV_FILE="${SPEAKSEL_DIR}/.current.wav"
STATE_FILE="${SPEAKSEL_DIR}/.state"

export DYLD_LIBRARY_PATH="${SPEAKSEL_DIR}/bin:${DYLD_LIBRARY_PATH:-}"

# Read config
VOICE="5"  # Default: am_adam
SPEED="1.0"
[[ -f "${SPEAKSEL_DIR}/voice" ]] && VOICE=$(cat "${SPEAKSEL_DIR}/voice" | tr -d '[:space:]')
[[ -f "${SPEAKSEL_DIR}/speed" ]] && SPEED=$(cat "${SPEAKSEL_DIR}/speed" | tr -d '[:space:]')

# --- Commands ---

stop_playback() {
    if [[ -f "${PID_FILE}" ]]; then
        kill $(cat "${PID_FILE}") 2>/dev/null || true
        rm -f "${PID_FILE}"
    fi
    pkill -f "afplay.*speaksel" 2>/dev/null || true
    echo "stopped" > "${STATE_FILE}"
}

pause_playback() {
    if [[ -f "${PID_FILE}" ]]; then
        kill -STOP $(cat "${PID_FILE}") 2>/dev/null || true
        echo "paused" > "${STATE_FILE}"
    fi
}

resume_playback() {
    if [[ -f "${PID_FILE}" ]]; then
        kill -CONT $(cat "${PID_FILE}") 2>/dev/null || true
        echo "playing" > "${STATE_FILE}"
    fi
}

toggle_playback() {
    if [[ -f "${STATE_FILE}" ]] && [[ "$(cat "${STATE_FILE}")" == "paused" ]]; then
        resume_playback
    elif [[ -f "${PID_FILE}" ]] && kill -0 $(cat "${PID_FILE}") 2>/dev/null; then
        pause_playback
    fi
}

set_speed() {
    echo "$1" > "${SPEAKSEL_DIR}/speed"
    echo "Speed set to $1"
}

get_status() {
    local state="stopped"
    [[ -f "${STATE_FILE}" ]] && state=$(cat "${STATE_FILE}")
    local voice="${VOICE}"
    local speed="${SPEED}"
    echo "{\"state\":\"${state}\",\"voice\":\"${voice}\",\"speed\":\"${speed}\"}"
}

speak_text() {
    local text="$1"

    # Skip if empty
    if [[ -z "${text}" ]]; then
        exit 0
    fi

    # Truncate very long text
    text="${text:0:10000}"

    # Stop any current playback
    stop_playback

    # Generate speech
    "${TTS_BIN}" \
        --kokoro-model="${MODEL_DIR}/model.onnx" \
        --kokoro-voices="${MODEL_DIR}/voices.bin" \
        --kokoro-tokens="${MODEL_DIR}/tokens.txt" \
        --kokoro-data-dir="${MODEL_DIR}/espeak-ng-data" \
        --kokoro-lexicon="${MODEL_DIR}/lexicon-us-en.txt" \
        --num-threads=2 \
        --sid="${VOICE}" \
        --kokoro-length-scale="$(awk -v s="${SPEED}" 'BEGIN{printf "%.2f", 1/s}')" \
        --output-filename="${WAV_FILE}" \
        "${text}" >/dev/null 2>&1

    # Play audio
    if [[ -f "${WAV_FILE}" ]]; then
        echo "playing" > "${STATE_FILE}"
        afplay "${WAV_FILE}" &
        echo $! > "${PID_FILE}"
        # Monitor and clean up when done
        (
            wait $! 2>/dev/null
            echo "stopped" > "${STATE_FILE}"
            rm -f "${PID_FILE}"
        ) &
    fi
}

# --- Main ---

case "${1:-speak}" in
    stop)
        stop_playback
        ;;
    pause)
        pause_playback
        ;;
    resume)
        resume_playback
        ;;
    toggle)
        toggle_playback
        ;;
    speed)
        set_speed "${2:-1.0}"
        ;;
    status)
        get_status
        ;;
    speak|*)
        if [[ "${1:-}" == "speak" ]]; then
            shift || true
        fi
        # Text from args or stdin
        if [[ $# -gt 0 ]]; then
            speak_text "$*"
        else
            TEXT=$(cat)
            speak_text "${TEXT}"
        fi
        ;;
esac
