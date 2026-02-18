# Vox 🗣️

**Highlight → Right-Click → Speak** — Natural AI-powered text-to-speech for macOS.

Uses [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) (82M parameter open-weight TTS) via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) for lifelike speech. No cloud API, no subscription — runs 100% locally on your Mac.

## Installation

### Option 1: Download Release (Recommended)

1. Go to [Releases](../../releases) and download the latest `Vox-macOS.zip`
2. Unzip it
3. Run the installer:
   ```bash
   cd Vox-macOS
   ./install.sh
   ```
4. Follow the prompts — it will:
   - Install the TTS engine + Kokoro model to `~/.vox/`
   - Install the macOS Quick Action (right-click menu)
   - Verify everything works

### Option 2: Build from Source

```bash
git clone https://github.com/tlockcuff/vox.git
cd vox
./scripts/build.sh
./install.sh
```

## Usage

1. **Highlight any text** in any macOS application
2. **Right-click** → **Services** → **Speak with Vox**
3. 🔊 Audio plays immediately

### Keyboard Shortcut (Optional)

After installing, go to **System Settings → Keyboard → Keyboard Shortcuts → Services → Text** and assign a shortcut to "Speak with Vox" (e.g., `⌘⇧S`).

## Voices

Vox ships with 11 English Kokoro voices:

| ID | Name | Description |
|----|------|-------------|
| 0 | af | American Female (default) |
| 1 | af_bella | American Female - Bella |
| 2 | af_nicole | American Female - Nicole |
| 3 | af_sarah | American Female - Sarah |
| 4 | af_sky | American Female - Sky |
| 5 | am_adam | American Male - Adam |
| 6 | am_michael | American Male - Michael |
| 7 | bf_emma | British Female - Emma |
| 8 | bf_isabella | British Female - Isabella |
| 9 | bm_george | British Male - George |
| 10 | bm_lewis | British Male - Lewis |

### Change Voice

```bash
# Set voice by speaker ID
echo "5" > ~/.vox/voice

# Or set speed (default 1.0, range 0.5-2.0)
echo "1.2" > ~/.vox/speed
```

## Configuration

Config files live in `~/.vox/`:

- `voice` — Speaker ID (0-10, default: 5 for am_adam)
- `speed` — Playback speed multiplier (default: 1.0)

## Uninstall

```bash
~/.vox/uninstall.sh
```

## How It Works

1. macOS Quick Action captures selected text
2. Text is piped to `sherpa-onnx-offline-tts` with the Kokoro model
3. Audio is generated locally as WAV
4. `afplay` plays the audio (with optional speed adjustment)
5. Temp files are cleaned up

No internet required. No data leaves your machine.

## Requirements

- macOS 12+ (Monterey or later)
- Apple Silicon (M1/M2/M3) or Intel Mac
- ~400MB disk space (model + engine)

## License

MIT — Kokoro model weights are Apache 2.0 licensed.
