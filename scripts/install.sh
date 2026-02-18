#!/usr/bin/env bash
# SpeakSel Installer — handles fresh install and updates
set -euo pipefail

SPEAKSEL_DIR="${HOME}/.speaksel"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="${SPEAKSEL_DIR}/.version"

echo "🗣️  SpeakSel Installer"
echo "====================="
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

# Stop existing app if running
echo "🔄 Stopping existing SpeakSel..."
pkill -f "SpeakSel" 2>/dev/null || true
launchctl unload "${HOME}/Library/LaunchAgents/com.speaksel.app.plist" 2>/dev/null || true
sleep 1

# Create directories
mkdir -p "${SPEAKSEL_DIR}/bin"

# --- Install binaries ---
if [[ -f "${SCRIPT_DIR}/bin/sherpa-onnx-offline-tts" ]]; then
    echo "📋 Installing from release package..."
    cp -f "${SCRIPT_DIR}/bin/"* "${SPEAKSEL_DIR}/bin/"
    if [[ -d "${SCRIPT_DIR}/kokoro-en-v0_19" ]]; then
        # Only copy model if not already installed (it's big)
        if [[ ! -f "${SPEAKSEL_DIR}/kokoro-en-v0_19/model.onnx" ]]; then
            echo "📦 Installing Kokoro model (~350MB)..."
            cp -r "${SCRIPT_DIR}/kokoro-en-v0_19" "${SPEAKSEL_DIR}/"
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
    cp "${SHERPA_DIR}/bin/sherpa-onnx-offline-tts" "${SPEAKSEL_DIR}/bin/"
    cp "${SHERPA_DIR}/lib/"*.dylib "${SPEAKSEL_DIR}/bin/" 2>/dev/null || true

    if [[ ! -f "${SPEAKSEL_DIR}/kokoro-en-v0_19/model.onnx" ]]; then
        echo "📥 Downloading Kokoro English model..."
        curl -sL "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2" -o "${TMPFILE}/kokoro.tar.bz2"
        echo "📦 Extracting model (~350MB)..."
        cd "${SPEAKSEL_DIR}" && tar xf "${TMPFILE}/kokoro.tar.bz2"
    fi
    rm -rf "${TMPFILE}"
fi

# --- Install menu bar app ---
if [[ -f "${SCRIPT_DIR}/SpeakSel" ]]; then
    echo "🖥️  Installing menu bar app..."
    cp -f "${SCRIPT_DIR}/SpeakSel" "${SPEAKSEL_DIR}/bin/SpeakSel"
elif [[ -f "${SCRIPT_DIR}/../SpeakSelApp/.build/release/SpeakSel" ]]; then
    echo "🖥️  Installing menu bar app (from source)..."
    cp -f "${SCRIPT_DIR}/../SpeakSelApp/.build/release/SpeakSel" "${SPEAKSEL_DIR}/bin/SpeakSel"
fi

# --- Codesign all binaries (required by macOS Gatekeeper) ---
echo "🔐 Codesigning binaries..."
xattr -cr "${SPEAKSEL_DIR}/bin/" 2>/dev/null || true
for f in "${SPEAKSEL_DIR}/bin/"*.dylib; do
    codesign --force --sign - "$f" 2>/dev/null || true
done
codesign --force --sign - "${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts" 2>/dev/null || true
if [[ -f "${SPEAKSEL_DIR}/bin/SpeakSel" ]]; then
    codesign --force --sign - "${SPEAKSEL_DIR}/bin/SpeakSel" 2>/dev/null || true
fi
chmod +x "${SPEAKSEL_DIR}/bin/"*

# --- Install shell script ---
cp -f "${SCRIPT_DIR}/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh" 2>/dev/null || \
    cp -f "${SCRIPT_DIR}/../scripts/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh" 2>/dev/null || \
    cp -f "${SCRIPT_DIR}/scripts/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh" 2>/dev/null || true
chmod +x "${SPEAKSEL_DIR}/speaksel.sh"

# --- Default config (don't overwrite existing) ---
[[ -f "${SPEAKSEL_DIR}/voice" ]] || echo "5" > "${SPEAKSEL_DIR}/voice"
[[ -f "${SPEAKSEL_DIR}/speed" ]] || echo "1.0" > "${SPEAKSEL_DIR}/speed"
touch "${SPEAKSEL_DIR}/.request"

# --- macOS Quick Action ---
echo "🔧 Installing Quick Action..."
SERVICES_DIR="${HOME}/Library/Services"
mkdir -p "${SERVICES_DIR}"
WORKFLOW_DIR="${SERVICES_DIR}/Speak with SpeakSel.workflow"
mkdir -p "${WORKFLOW_DIR}/Contents"

cat > "${WORKFLOW_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Speak with SpeakSel</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSSendTypes</key>
			<array>
				<string>NSStringPboardType</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

cat > "${WORKFLOW_DIR}/Contents/document.wflow" << 'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMCategory</key>
				<string>AMCategoryUtilities</string>
				<key>AMIconName</key>
				<string>Run Shell Script</string>
				<key>AMName</key>
				<string>Run Shell Script</string>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMRequiredResources</key>
				<array/>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>export DYLD_LIBRARY_PATH="${HOME}/.speaksel/bin:${DYLD_LIBRARY_PATH:-}"
echo "$@" | "${HOME}/.speaksel/speaksel.sh"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>A1A1A1A1-B2B2-C3C3-D4D4-E5E5E5E5E5E5</string>
				<key>OutputUUID</key>
				<string>F6F6F6F6-A7A7-B8B8-C9C9-D0D0D0D0D0D0</string>
				<key>UUID</key>
				<string>12345678-1234-1234-1234-123456789ABC</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict/>
				<key>isViewVisible</key>
				<integer>1</integer>
			</dict>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

# --- Launch Agent (auto-start on login) ---
if [[ -f "${SPEAKSEL_DIR}/bin/SpeakSel" ]]; then
    LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
    mkdir -p "${LAUNCH_AGENT_DIR}"
    cat > "${LAUNCH_AGENT_DIR}/com.speaksel.app.plist" << LAUNCHPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.speaksel.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SPEAKSEL_DIR}/bin/SpeakSel</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DYLD_LIBRARY_PATH</key>
        <string>${SPEAKSEL_DIR}/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAUNCHPLIST

    # Launch the app
    launchctl load "${LAUNCH_AGENT_DIR}/com.speaksel.app.plist" 2>/dev/null || true
    # Also start directly in case launchctl doesn't trigger immediately
    DYLD_LIBRARY_PATH="${SPEAKSEL_DIR}/bin" nohup "${SPEAKSEL_DIR}/bin/SpeakSel" &>/dev/null &
    echo "✅ Menu bar app installed & launched"
fi

# --- Update script ---
cat > "${SPEAKSEL_DIR}/update.sh" << 'UPDATE'
#!/usr/bin/env bash
set -euo pipefail
echo "🔄 Updating SpeakSel..."

# Need gh CLI
if ! command -v gh &>/dev/null; then
    echo "📥 Installing GitHub CLI..."
    brew install gh 2>/dev/null || { echo "❌ Need 'gh' CLI. Install with: brew install gh"; exit 1; }
fi

REPO="tlockcuff/speaksel"
TMPDIR=$(mktemp -d)

echo "📥 Downloading latest release..."
gh release download --repo "${REPO}" --pattern "*.zip" --dir "${TMPDIR}" 2>/dev/null || {
    echo "❌ Download failed. Make sure you're authenticated: gh auth login"
    exit 1
}

ZIP=$(ls "${TMPDIR}"/*.zip | head -1)
echo "📦 Extracting..."
cd "${TMPDIR}" && unzip -qo "${ZIP}"
DIR=$(ls -d "${TMPDIR}"/SpeakSel-macOS* | head -1)

echo "🔧 Installing..."
cd "${DIR}" && bash ./install.sh

rm -rf "${TMPDIR}"
echo "✅ Update complete!"
UPDATE
chmod +x "${SPEAKSEL_DIR}/update.sh"

# --- Uninstall script ---
cat > "${SPEAKSEL_DIR}/uninstall.sh" << 'UNINSTALL'
#!/usr/bin/env bash
echo "🗑️  Uninstalling SpeakSel..."
pkill -f "SpeakSel" 2>/dev/null || true
launchctl unload "${HOME}/Library/LaunchAgents/com.speaksel.app.plist" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/com.speaksel.app.plist"
rm -rf "${HOME}/.speaksel"
rm -rf "${HOME}/Library/Services/Speak with SpeakSel.workflow"
echo "✅ SpeakSel removed."
UNINSTALL
chmod +x "${SPEAKSEL_DIR}/uninstall.sh"

# --- Save version ---
echo "v0.3.0" > "${VERSION_FILE}"

# Refresh services
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "✅ SpeakSel installed successfully!"
echo ""
echo "📍 Install:  ${SPEAKSEL_DIR}/"
echo "📍 Action:   ~/Library/Services/Speak with SpeakSel.workflow"
echo ""
echo "🎯 Usage:"
echo "   • Highlight text → Right-click → Services → Speak with SpeakSel"
echo "   • Click the 🔊 menu bar icon for playback controls"
echo ""
echo "🔄 Update:     ~/.speaksel/update.sh"
echo "🗑️  Uninstall:  ~/.speaksel/uninstall.sh"
echo ""
echo "⌨️  Tip: Set a keyboard shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services"
echo ""

# Quick test
echo "🧪 Running quick test..."
export DYLD_LIBRARY_PATH="${SPEAKSEL_DIR}/bin:${DYLD_LIBRARY_PATH:-}"
echo 'SpeakSel is ready to go!' | "${SPEAKSEL_DIR}/speaksel.sh" && echo "✅ Test passed!" || echo "⚠️  Test failed"
