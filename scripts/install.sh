#!/usr/bin/env bash
# SpeakSel Installer
set -euo pipefail

SPEAKSEL_DIR="${HOME}/.speaksel"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
echo ""

# Create directories
mkdir -p "${SPEAKSEL_DIR}/bin"

# Check if this is a release install (pre-bundled) or from source
if [[ -f "${SCRIPT_DIR}/bin/sherpa-onnx-offline-tts" ]]; then
    echo "📋 Installing from release package..."
    cp -r "${SCRIPT_DIR}/bin/"* "${SPEAKSEL_DIR}/bin/"
    cp -r "${SCRIPT_DIR}/kokoro-en-v0_19" "${SPEAKSEL_DIR}/"
else
    echo "📥 Downloading sherpa-onnx..."
    SHERPA_VERSION="v1.12.25"
    SHERPA_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-osx-universal2-shared.tar.bz2"

    TMPFILE=$(mktemp -d)
    curl -sL "${SHERPA_URL}" -o "${TMPFILE}/sherpa.tar.bz2"
    echo "📦 Extracting sherpa-onnx..."
    cd "${TMPFILE}"
    tar xf sherpa.tar.bz2
    SHERPA_DIR=$(ls -d sherpa-onnx-*)

    # Copy the TTS binary and required libraries
    cp "${SHERPA_DIR}/bin/sherpa-onnx-offline-tts" "${SPEAKSEL_DIR}/bin/"
    cp "${SHERPA_DIR}/lib/"*.dylib "${SPEAKSEL_DIR}/bin/" 2>/dev/null || true
    chmod +x "${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts"

    echo "📥 Downloading Kokoro English model..."
    MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"
    curl -sL "${MODEL_URL}" -o "${TMPFILE}/kokoro.tar.bz2"
    echo "📦 Extracting model (~350MB)..."
    cd "${SPEAKSEL_DIR}"
    tar xf "${TMPFILE}/kokoro.tar.bz2"

    # Cleanup
    rm -rf "${TMPFILE}"
    cd "${SPEAKSEL_DIR}"
fi

# Install the speak script
cp "${SCRIPT_DIR}/../scripts/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh" 2>/dev/null || \
    cp "${SCRIPT_DIR}/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh" 2>/dev/null || \
    cp "${SCRIPT_DIR}/scripts/speaksel.sh" "${SPEAKSEL_DIR}/speaksel.sh"
chmod +x "${SPEAKSEL_DIR}/speaksel.sh"

# Set default config
[[ -f "${SPEAKSEL_DIR}/voice" ]] || echo "5" > "${SPEAKSEL_DIR}/voice"
[[ -f "${SPEAKSEL_DIR}/speed" ]] || echo "1.0" > "${SPEAKSEL_DIR}/speed"

# Install the macOS Quick Action
echo "🔧 Installing macOS Quick Action..."
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
				<key>AMKeywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
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
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>F6F6F6F6-A7A7-B8B8-C9C9-D0D0D0D0D0D0</string>
				<key>UUID</key>
				<string>12345678-1234-1234-1234-123456789ABC</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<integer>0</integer>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<integer>4</integer>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<integer>0</integer>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<integer>4</integer>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<integer>4</integer>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>449.000000:620.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
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

# Install uninstaller
cat > "${SPEAKSEL_DIR}/uninstall.sh" << 'UNINSTALL'
#!/usr/bin/env bash
echo "🗑️  Uninstalling SpeakSel..."
rm -rf "${HOME}/.speaksel"
rm -rf "${HOME}/Library/Services/Speak with SpeakSel.workflow"
echo "✅ SpeakSel has been removed."
UNINSTALL
chmod +x "${SPEAKSEL_DIR}/uninstall.sh"

# Refresh services
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "✅ SpeakSel installed successfully!"
echo ""
echo "📍 Engine: ${SPEAKSEL_DIR}/bin/sherpa-onnx-offline-tts"
echo "📍 Model:  ${SPEAKSEL_DIR}/kokoro-en-v0_19/"
echo "📍 Action: ~/Library/Services/Speak with SpeakSel.workflow"
echo ""
echo "🎯 Usage: Highlight text → Right-click → Services → Speak with SpeakSel"
echo ""
echo "⌨️  Tip: Set a keyboard shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services → Text"
echo ""

# Quick test
echo "🧪 Running quick test..."
export DYLD_LIBRARY_PATH="${SPEAKSEL_DIR}/bin:${DYLD_LIBRARY_PATH:-}"
echo "SpeakSel is ready to go!" | "${SPEAKSEL_DIR}/speaksel.sh" && echo "✅ Test passed! You should hear audio." || echo "⚠️  Test failed — check the output above."
