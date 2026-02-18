#!/usr/bin/env bash
# Vox Installer — handles fresh install and updates
set -euo pipefail

VOX_DIR="${HOME}/.vox"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="${VOX_DIR}/.version"

echo "🎙️  Vox Installer"
echo "================="
echo ""

# Detect architecture
ARCH=$(uname -m)
if [[ "${ARCH}" == "arm64" ]]; then
    PLATFORM="arm64"
elif [[ "${ARCH}" == "x86_64" ]]; then
    PLATFORM="x64"
else
    echo "❌ Unsupported architecture: ${ARCH}"
    exit 1
fi
echo "📦 Detected: macOS ${PLATFORM}"

# --- Clean up old SpeakSel installation ---
if [[ -d "${HOME}/.speaksel" ]]; then
    echo "🧹 Removing old SpeakSel installation..."
    pkill -f "SpeakSel" 2>/dev/null || true
    launchctl unload "${HOME}/Library/LaunchAgents/com.speaksel.app.plist" 2>/dev/null || true
    rm -f "${HOME}/Library/LaunchAgents/com.speaksel.app.plist"
    rm -rf "${HOME}/Library/Services/Speak with SpeakSel.workflow"
    # Migrate config but not binaries
    [[ -f "${HOME}/.speaksel/voice" ]] && mkdir -p "${VOX_DIR}" && cp "${HOME}/.speaksel/voice" "${VOX_DIR}/voice" 2>/dev/null || true
    [[ -f "${HOME}/.speaksel/speed" ]] && mkdir -p "${VOX_DIR}" && cp "${HOME}/.speaksel/speed" "${VOX_DIR}/speed" 2>/dev/null || true
    rm -rf "${HOME}/.speaksel"
    echo "✅ Old SpeakSel removed"
fi

# Stop existing app if running
echo "🔄 Stopping existing Vox..."
pkill -f "Vox" 2>/dev/null || true
launchctl unload "${HOME}/Library/LaunchAgents/com.vox.app.plist" 2>/dev/null || true
sleep 1

# Create directories
mkdir -p "${VOX_DIR}/bin"

# --- Install binaries ---
if [[ -f "${SCRIPT_DIR}/bin/sherpa-onnx-offline-tts" ]]; then
    echo "📋 Installing from release package..."
    cp -f "${SCRIPT_DIR}/bin/"* "${VOX_DIR}/bin/"
    if [[ -d "${SCRIPT_DIR}/kokoro-en-v0_19" ]]; then
        if [[ ! -f "${VOX_DIR}/kokoro-en-v0_19/model.onnx" ]]; then
            echo "📦 Installing Kokoro model (~350MB)..."
            cp -r "${SCRIPT_DIR}/kokoro-en-v0_19" "${VOX_DIR}/"
        else
            echo "📦 Model already installed, skipping..."
        fi
    fi
else
    echo "📥 Downloading sherpa-onnx..."
    SHERPA_VERSION="v1.12.25"
    TMPFILE=$(mktemp -d)
    curl -sL "https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-osx-universal2-shared.tar.bz2" -o "${TMPFILE}/sherpa.tar.bz2"
    echo "📦 Extracting sherpa-onnx..."
    cd "${TMPFILE}" && tar xf sherpa.tar.bz2
    SHERPA_DIR=$(ls -d sherpa-onnx-*)
    cp "${SHERPA_DIR}/bin/sherpa-onnx-offline-tts" "${VOX_DIR}/bin/"
    cp "${SHERPA_DIR}/lib/"*.dylib "${VOX_DIR}/bin/" 2>/dev/null || true

    if [[ ! -f "${VOX_DIR}/kokoro-en-v0_19/model.onnx" ]]; then
        echo "📥 Downloading Kokoro English model..."
        curl -sL "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2" -o "${TMPFILE}/kokoro.tar.bz2"
        echo "📦 Extracting model (~350MB)..."
        cd "${VOX_DIR}" && tar xf "${TMPFILE}/kokoro.tar.bz2"
    fi
    rm -rf "${TMPFILE}"
fi

# --- Install menu bar app ---
if [[ -f "${SCRIPT_DIR}/Vox" ]]; then
    echo "🖥️  Installing menu bar app..."
    cp -f "${SCRIPT_DIR}/Vox" "${VOX_DIR}/bin/Vox"
elif [[ -f "${SCRIPT_DIR}/../VoxApp/.build/release/Vox" ]]; then
    echo "🖥️  Installing menu bar app (from source)..."
    cp -f "${SCRIPT_DIR}/../VoxApp/.build/release/Vox" "${VOX_DIR}/bin/Vox"
fi

# --- Codesign all binaries ---
echo "🔐 Codesigning binaries..."
xattr -cr "${VOX_DIR}/bin/"
for f in "${VOX_DIR}/bin/"*.dylib; do
    [ -f "$f" ] && codesign --force --deep --sign - "$f" 2>/dev/null
done
[ -f "${VOX_DIR}/bin/sherpa-onnx-offline-tts" ] && codesign --force --deep --sign - "${VOX_DIR}/bin/sherpa-onnx-offline-tts"
[ -f "${VOX_DIR}/bin/Vox" ] && codesign --force --deep --sign - "${VOX_DIR}/bin/Vox"
chmod +x "${VOX_DIR}/bin/"*
echo "✅ Codesigning complete"

# --- Install shell script ---
cp -f "${SCRIPT_DIR}/vox.sh" "${VOX_DIR}/vox.sh" 2>/dev/null || \
    cp -f "${SCRIPT_DIR}/../scripts/vox.sh" "${VOX_DIR}/vox.sh" 2>/dev/null || \
    cp -f "${SCRIPT_DIR}/scripts/vox.sh" "${VOX_DIR}/vox.sh" 2>/dev/null || true
chmod +x "${VOX_DIR}/vox.sh"

# --- Default config (don't overwrite existing) ---
[[ -f "${VOX_DIR}/voice" ]] || echo "5" > "${VOX_DIR}/voice"
[[ -f "${VOX_DIR}/speed" ]] || echo "1.0" > "${VOX_DIR}/speed"
touch "${VOX_DIR}/.request"

# --- Launch Agent (auto-start on login) ---
if [[ -f "${VOX_DIR}/bin/Vox" ]]; then
    LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
    mkdir -p "${LAUNCH_AGENT_DIR}"
    cat > "${LAUNCH_AGENT_DIR}/com.vox.app.plist" << LAUNCHPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vox.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>${VOX_DIR}/bin/Vox</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DYLD_LIBRARY_PATH</key>
        <string>${VOX_DIR}/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAUNCHPLIST

    launchctl load "${LAUNCH_AGENT_DIR}/com.vox.app.plist" 2>/dev/null || true
    DYLD_LIBRARY_PATH="${VOX_DIR}/bin" nohup "${VOX_DIR}/bin/Vox" &>/dev/null &
    echo "✅ Menu bar app installed & launched"
fi

# --- Update script ---
cat > "${VOX_DIR}/update.sh" << 'UPDATE'
#!/usr/bin/env bash
set -euo pipefail
echo "🔄 Updating Vox..."

if ! command -v gh &>/dev/null; then
    echo "📥 Installing GitHub CLI..."
    brew install gh 2>/dev/null || { echo "❌ Need 'gh' CLI. Install with: brew install gh"; exit 1; }
fi

REPO="tlockcuff/vox"
TMPDIR=$(mktemp -d)

echo "📥 Downloading latest release..."
gh release download --repo "${REPO}" --pattern "*.zip" --dir "${TMPDIR}" 2>/dev/null || {
    echo "❌ Download failed. Make sure you're authenticated: gh auth login"
    exit 1
}

ZIP=$(ls "${TMPDIR}"/*.zip | head -1)
echo "📦 Extracting..."
cd "${TMPDIR}" && unzip -qo "${ZIP}"
DIR=$(ls -d "${TMPDIR}"/Vox-macOS* | head -1)

echo "🔧 Installing..."
cd "${DIR}" && bash ./install.sh

rm -rf "${TMPDIR}"
echo "✅ Update complete!"
UPDATE
chmod +x "${VOX_DIR}/update.sh"

# --- Uninstall script ---
cat > "${VOX_DIR}/uninstall.sh" << 'UNINSTALL'
#!/usr/bin/env bash
echo "🗑️  Uninstalling Vox..."
pkill -f "Vox" 2>/dev/null || true
launchctl unload "${HOME}/Library/LaunchAgents/com.vox.app.plist" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/com.vox.app.plist"
rm -rf "${HOME}/.vox"
rm -rf "${HOME}/Library/Services/Speak with Vox.workflow"
echo "✅ Vox removed."
UNINSTALL
chmod +x "${VOX_DIR}/uninstall.sh"

# --- Save version ---
echo "v0.5.0" > "${VERSION_FILE}"

# Refresh services
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "✅ Vox installed successfully!"
echo ""
echo "📍 Install:  ${VOX_DIR}/"
echo "📍 Action:   ~/Library/Services/Speak with Vox.workflow"
echo ""
echo "🎯 Usage:"
echo "   • Highlight text → Right-click → Services → Speak with Vox"
echo "   • Click the 🎙️ menu bar icon for playback controls"
echo ""
echo "🔄 Update:     ~/.vox/update.sh"
echo "🗑️  Uninstall:  ~/.vox/uninstall.sh"
