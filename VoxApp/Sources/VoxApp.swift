import SwiftUI
import AppKit
import AVFoundation
import Sparkle

// Pure AppDelegate entry — no SwiftUI App lifecycle, no Settings window
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var engine = TTSEngine.shared

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Close any windows (there shouldn't be any now)
        for window in NSApp.windows { window.close() }

        // First-launch setup
        FirstLaunchSetup.run()

        // Static menu bar icon — never changes
        statusItem = NSStatusBar.system.statusItem(withLength: 22)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vox")
            img?.isTemplate = true
            img?.size = NSSize(width: 16, height: 16)
            button.image = img
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ControlsView())

        engine.startWatching()
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// MARK: - First Launch Setup

struct FirstLaunchSetup {
    static func run() {
        let configDir = Paths.configDir
        let fm = FileManager.default

        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(configDir)/bin", withIntermediateDirectories: true)

        let voiceFile = "\(configDir)/voice"
        let speedFile = "\(configDir)/speed"
        if !fm.fileExists(atPath: voiceFile) { try? "5".write(toFile: voiceFile, atomically: true, encoding: .utf8) }
        if !fm.fileExists(atPath: speedFile) { try? "1.0".write(toFile: speedFile, atomically: true, encoding: .utf8) }

        let requestFile = "\(Paths.legacyDir)/.request"
        if !fm.fileExists(atPath: requestFile) { fm.createFile(atPath: requestFile, contents: nil) }

        let version = AppVersion.current
        try? version.write(toFile: "\(configDir)/.version", atomically: true, encoding: .utf8)
        // Also write to legacy dir
        try? version.write(toFile: "\(Paths.legacyDir)/.version", atomically: true, encoding: .utf8)

        extractBundleResources()

        // Download model if needed (async — UI shows progress)
        if !Paths.modelExists {
            ModelDownloader.shared.downloadModel()
        }

        // Remove old SpeakSel remnants
        let oldWorkflow = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services/Speak with SpeakSel.workflow").path
        if fm.fileExists(atPath: oldWorkflow) { try? fm.removeItem(atPath: oldWorkflow) }

        installQuickAction()
        installShellHelper()

        log("FirstLaunchSetup complete. TTS bin exists: \(fm.fileExists(atPath: Paths.ttsBin)), Model exists: \(fm.fileExists(atPath: "\(Paths.modelDir)/model.onnx"))")
    }

    static func extractBundleResources() {
        let fm = FileManager.default
        let configDir = Paths.configDir
        let binDir = "\(configDir)/bin"

        let frameworksDir = Bundle.main.bundlePath + "/Contents/Frameworks"
        log("Extracting from bundle: \(frameworksDir) exists=\(fm.fileExists(atPath: frameworksDir))")

        if fm.fileExists(atPath: frameworksDir) {
            if let files = try? fm.contentsOfDirectory(atPath: frameworksDir) {
                log("Bundle Frameworks contents: \(files)")
                for file in files {
                    let src = "\(frameworksDir)/\(file)"
                    let dst = "\(binDir)/\(file)"
                    try? fm.removeItem(atPath: dst)
                    do {
                        try fm.copyItem(atPath: src, toPath: dst)
                        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
                        log("Extracted: \(file)")
                    } catch {
                        log("Failed to extract \(file): \(error)")
                    }
                }
            }
        }

        let bundleModelDir = Bundle.main.bundlePath + "/Contents/Resources/kokoro-en-v0_19"
        let localModelDir = "\(configDir)/kokoro-en-v0_19"
        log("Bundle model dir exists: \(fm.fileExists(atPath: bundleModelDir)), local model exists: \(fm.fileExists(atPath: "\(localModelDir)/model.onnx"))")

        if fm.fileExists(atPath: bundleModelDir) && !fm.fileExists(atPath: "\(localModelDir)/model.onnx") {
            do {
                try fm.copyItem(atPath: bundleModelDir, toPath: localModelDir)
                log("Model extracted to \(localModelDir)")
            } catch {
                log("Failed to extract model: \(error)")
            }
        }

        // Codesign extracted binaries
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", """
            cd "\(binDir)"
            xattr -cr . 2>/dev/null
            for f in *.dylib; do [ -f "$f" ] && codesign --force --sign - "$f" 2>/dev/null; done
            [ -f sherpa-onnx-offline-tts ] && codesign --force --sign - sherpa-onnx-offline-tts 2>/dev/null
            true
        """]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        log("Codesign complete")
    }

    static func installQuickAction() {
        let servicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services").path
        try? FileManager.default.createDirectory(atPath: servicesDir, withIntermediateDirectories: true)

        let workflowDir = "\(servicesDir)/Speak with Vox.workflow/Contents"
        try? FileManager.default.createDirectory(atPath: workflowDir, withIntermediateDirectories: true)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict><key>default</key><string>Speak with Vox</string></dict>
                    <key>NSMessage</key><string>runWorkflowAsService</string>
                    <key>NSSendTypes</key>
                    <array><string>NSStringPboardType</string></array>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let configDir = Paths.configDir
        let wflow = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key><string>523</string>
            <key>AMApplicationVersion</key><string>2.10</string>
            <key>AMDocumentVersion</key><string>2</string>
            <key>actions</key>
            <array><dict><key>action</key><dict>
                <key>AMAccepts</key><dict><key>Container</key><string>List</string><key>Optional</key><true/><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
                <key>AMActionVersion</key><string>2.0.3</string>
                <key>AMApplication</key><array><string>Automator</string></array>
                <key>AMCategory</key><string>AMCategoryUtilities</string>
                <key>AMName</key><string>Run Shell Script</string>
                <key>AMProvides</key><dict><key>Container</key><string>List</string><key>Types</key><array><string>com.apple.cocoa.string</string></array></dict>
                <key>AMRequiredResources</key><array/>
                <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key><string>Run Shell Script</string>
                <key>ActionParameters</key><dict>
                    <key>COMMAND_STRING</key><string>echo "$@" | "\(configDir)/vox.sh"</string>
                    <key>CheckedForUserDefaultShell</key><true/>
                    <key>inputMethod</key><integer>1</integer>
                    <key>shell</key><string>/bin/bash</string>
                    <key>source</key><string></string>
                </dict>
                <key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key><string>2.0.3</string>
                <key>CanShowSelectedItemsWhenRun</key><false/>
                <key>CanShowWhenRun</key><true/>
                <key>Class Name</key><string>RunShellScriptAction</string>
                <key>InputUUID</key><string>A1A1A1A1-B2B2-C3C3-D4D4-E5E5E5E5E5E5</string>
                <key>OutputUUID</key><string>F6F6F6F6-A7A7-B8B8-C9C9-D0D0D0D0D0D0</string>
                <key>UUID</key><string>12345678-1234-1234-1234-123456789ABC</string>
                <key>arguments</key><dict/>
                <key>isViewVisible</key><integer>1</integer>
            </dict></dict></array>
            <key>connectors</key><dict/>
            <key>workflowMetaData</key><dict>
                <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """

        try? infoPlist.write(toFile: "\(workflowDir)/Info.plist", atomically: true, encoding: .utf8)
        try? wflow.write(toFile: "\(workflowDir)/document.wflow", atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-flush"]
        try? process.run()
    }

    static func installShellHelper() {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        VOX_DIR="${HOME}/.vox"
        REQUEST_FILE="${VOX_DIR}/.request"

        case "${1:-speak}" in
            stop)    echo "__STOP__" > "${REQUEST_FILE}" ;;
            toggle)  echo "__TOGGLE__" > "${REQUEST_FILE}" ;;
            speak|*)
                [[ "${1:-}" == "speak" ]] && shift || true
                if [[ $# -gt 0 ]]; then
                    echo "$*" > "${REQUEST_FILE}"
                else
                    cat > "${REQUEST_FILE}"
                fi
                ;;
        esac
        """
        let path = "\(Paths.configDir)/vox.sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", path]
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - App Version

struct AppVersion {
    static let current: String = {
        // 1. Try the .app bundle Info.plist (set by CI)
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, v != "1.0" {
            return v
        }
        // 2. Try reading from .app's Info.plist directly (for nested binary case)
        if Paths.isAppBundle {
            let plistPath = Bundle.main.bundlePath + "/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: plistPath),
               let v = dict["CFBundleShortVersionString"] as? String {
                return v
            }
        }
        // 3. Fallback
        return "0.6.0"
    }()
}

// MARK: - Logging

func log(_ message: String) {
    let logFile = "\(Paths.configDir)/vox.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
}

// MARK: - Paths

struct Paths {
    /// User data directory
    static let configDir: String = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vox").path
        // Also keep ~/.vox/ as alias for shell script compatibility
        let legacyDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vox").path
        try? FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: legacyDir, withIntermediateDirectories: true)
        return appSupport
    }()

    /// Legacy ~/.vox/ for shell script IPC
    static let legacyDir: String = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vox").path
    }()

    /// Are we running from inside a .app bundle?
    static let isAppBundle: Bool = {
        Bundle.main.bundlePath.hasSuffix(".app")
    }()

    /// TTS binary: .app bundle Frameworks or ~/.vox/bin/
    static var ttsBin: String {
        if isAppBundle {
            let bundlePath = Bundle.main.bundlePath + "/Contents/Frameworks/sherpa-onnx-offline-tts"
            if FileManager.default.fileExists(atPath: bundlePath) { return bundlePath }
        }
        let legacyPath = "\(legacyDir)/bin/sherpa-onnx-offline-tts"
        if FileManager.default.fileExists(atPath: legacyPath) { return legacyPath }
        return "\(configDir)/bin/sherpa-onnx-offline-tts"
    }

    /// Model directory (downloaded on first launch)
    static var modelDir: String {
        // Check multiple locations
        let appSupportModel = "\(configDir)/kokoro-en-v0_19"
        if FileManager.default.fileExists(atPath: "\(appSupportModel)/model.onnx") { return appSupportModel }
        let legacyModel = "\(legacyDir)/kokoro-en-v0_19"
        if FileManager.default.fileExists(atPath: "\(legacyModel)/model.onnx") { return legacyModel }
        if isAppBundle {
            let bundleModel = Bundle.main.bundlePath + "/Contents/Resources/kokoro-en-v0_19"
            if FileManager.default.fileExists(atPath: "\(bundleModel)/model.onnx") { return bundleModel }
        }
        return appSupportModel  // default location for download
    }

    /// Dylib directory
    static var libDir: String {
        if isAppBundle {
            return Bundle.main.bundlePath + "/Contents/Frameworks"
        }
        return "\(legacyDir)/bin"
    }

    static var modelExists: Bool {
        FileManager.default.fileExists(atPath: "\(modelDir)/model.onnx")
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let isActive: Bool
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            Canvas { context, size in
                let barCount = 32
                let barWidth = size.width / CGFloat(barCount) * 0.7
                let gap = size.width / CGFloat(barCount) * 0.3
                let maxHeight = size.height * 0.9

                for i in 0..<barCount {
                    let x = CGFloat(i) * (barWidth + gap) + gap / 2
                    let height: CGFloat
                    if isActive && !isPaused {
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let wave1 = sin(Double(i) * 0.4 + t * 4.0) * 0.3
                        let wave2 = sin(Double(i) * 0.7 + t * 2.5) * 0.2
                        let wave3 = cos(Double(i) * 0.3 + t * 3.2) * 0.15
                        let combined = 0.3 + abs(wave1 + wave2 + wave3)
                        height = maxHeight * CGFloat(min(combined, 0.95))
                    } else if isPaused {
                        let wave = sin(Double(i) * 0.5) * 0.2
                        height = maxHeight * CGFloat(0.25 + abs(wave))
                    } else {
                        height = maxHeight * 0.05
                    }
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let color: Color = isActive ? (isPaused ? .yellow : .green) : .secondary
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(isActive ? 0.8 : 0.3)))
                }
            }
        }
    }
}

// MARK: - Controls View

struct ControlsView: View {
    @ObservedObject var engine = TTSEngine.shared
    let speeds: [(String, Double)] = [
        ("0.5x", 0.5), ("0.75x", 0.75), ("1x", 1.0),
        ("1.25x", 1.25), ("1.5x", 1.5), ("2x", 2.0)
    ]

    var body: some View {
        VStack(spacing: 10) {
            WaveformView(isActive: engine.state != .stopped, isPaused: engine.state == .paused)
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.2)))

            HStack {
                Image(systemName: engine.state == .playing ? "speaker.wave.3.fill" :
                        engine.state == .paused ? "pause.circle.fill" : "waveform")
                    .foregroundColor(engine.state == .playing ? .green : engine.state == .paused ? .yellow : .secondary)
                    .font(.title3)
                Text(engine.state == .playing ? "Speaking" : engine.state == .paused ? "Paused" : "Idle")
                    .font(.headline)
                Spacer()
                if engine.state != .stopped {
                    Text(engine.etaText).font(.caption).foregroundColor(.secondary).monospacedDigit()
                }
            }

            if engine.state != .stopped {
                ProgressView(value: engine.progress).progressViewStyle(.linear)
                    .tint(engine.state == .paused ? .yellow : .green)
            }

            HStack(spacing: 20) {
                Button(action: { engine.toggle() }) {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 40, height: 40)
                }.buttonStyle(.plain).disabled(engine.state == .stopped)

                Button(action: { engine.stop() }) {
                    Image(systemName: "stop.fill").font(.title2).frame(width: 40, height: 40)
                }.buttonStyle(.plain).disabled(engine.state == .stopped)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $engine.speed) {
                        ForEach(speeds, id: \.1) { label, value in Text(label).tag(value) }
                    }.pickerStyle(.menu).frame(width: 70)
                    .onChange(of: engine.speed) { _ in engine.saveSpeed() }
                }
            }

            Divider()

            HStack {
                Image(systemName: "person.wave.2").foregroundColor(.secondary).font(.caption)
                Text("Voice").foregroundColor(.secondary).font(.caption)
                Picker("", selection: $engine.voiceId) {
                    ForEach(TTSEngine.voices, id: \.id) { voice in Text(voice.name).tag(voice.id) }
                }.pickerStyle(.menu).font(.caption)
                .onChange(of: engine.voiceId) { _ in engine.saveVoice() }
            }

            if engine.state != .stopped {
                HStack {
                    Text("\(engine.wordCount) words").font(.caption2).foregroundColor(.secondary)
                    Text("•").foregroundColor(.secondary)
                    Text("Chunk \(engine.currentIndex + 1)/\(engine.totalSentences)").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                }
            }

            if let errorMsg = engine.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.red).font(.caption)
                    Text(errorMsg).font(.caption2).foregroundColor(.red).lineLimit(3)
                    Spacer()
                }
            }

            ModelBannerView()

            Divider()
            UpdateBannerView()

            HStack {
                Text("v\(UpdaterViewModel.shared.currentVersion)").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Quit Vox") { NSApp.terminate(nil) }.font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Model Banner

struct ModelBannerView: View {
    @ObservedObject var downloader = ModelDownloader.shared

    var body: some View {
        if downloader.isDownloading {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle").foregroundColor(.blue).font(.caption)
                    Text("Downloading voice model...").font(.caption)
                    Spacer()
                    Text("\(Int(downloader.progress * 100))%").font(.caption).monospacedDigit().foregroundColor(.secondary)
                }
                ProgressView(value: downloader.progress).progressViewStyle(.linear).tint(.blue)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)))
        } else if let error = downloader.error {
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.orange).font(.caption)
                Text(error).font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Retry") { downloader.downloadModel() }.font(.caption2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
        } else if !Paths.modelExists {
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.orange).font(.caption)
                Text("Voice model not installed").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Download") { downloader.downloadModel() }.font(.caption).buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
        } else {
            EmptyView()
        }
    }
}

// MARK: - Update Banner

struct UpdateBannerView: View {
    @ObservedObject var updater = UpdaterViewModel.shared

    var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.secondary).font(.caption)
            Text("Check for Updates").font(.caption2).foregroundColor(.secondary)
            Spacer()
            Button("Check") { updater.checkForUpdates() }
                .font(.caption2)
                .disabled(!updater.canCheckForUpdates)
        }
    }
}

// MARK: - Data Types

struct Voice: Identifiable {
    let id: Int
    let name: String
}

enum PlaybackState {
    case stopped, playing, paused
}

// MARK: - Text Cleaner

struct TextCleaner {
    static func clean(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"https?://[^\s<>\]\)\"']+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]+\)"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?:/[\w.-]+){2,}"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^[\s]*[-*•]\s+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^[\s]*\d+\.\s+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - TTS Engine

class TTSEngine: ObservableObject {
    static let shared = TTSEngine()

    static let voices: [Voice] = [
        Voice(id: 0, name: "American Female"),
        Voice(id: 1, name: "AF - Bella"),
        Voice(id: 2, name: "AF - Nicole"),
        Voice(id: 3, name: "AF - Sarah"),
        Voice(id: 4, name: "AF - Sky"),
        Voice(id: 5, name: "AM - Adam"),
        Voice(id: 6, name: "AM - Michael"),
        Voice(id: 7, name: "BF - Emma"),
        Voice(id: 8, name: "BF - Isabella"),
        Voice(id: 9, name: "BM - George"),
        Voice(id: 10, name: "BM - Lewis"),
    ]

    private static let baseWPM: Double = 160

    @Published var state: PlaybackState = .stopped
    @Published var progress: Double = 0
    @Published var speed: Double = 1.0
    @Published var voiceId: Int = 5
    @Published var etaText: String = ""
    @Published var wordCount: Int = 0
    @Published var currentIndex: Int = 0
    @Published var totalSentences: Int = 0
    @Published var lastError: String?

    private var generateQueue: [String] = []
    private var audioFiles: [String] = []
    private var player: Process?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var totalWords: Int = 0
    private var spokenWords: Int = 0
    private var etaTimer: Timer?

    init() { loadConfig() }

    func loadConfig() {
        if let v = try? String(contentsOfFile: "\(Paths.configDir)/voice", encoding: .utf8) {
            voiceId = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5
        }
        if let s = try? String(contentsOfFile: "\(Paths.configDir)/speed", encoding: .utf8) {
            speed = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
        }
    }

    func saveSpeed() {
        try? String(speed).write(toFile: "\(Paths.configDir)/speed", atomically: true, encoding: .utf8)
    }

    func saveVoice() {
        try? String(voiceId).write(toFile: "\(Paths.configDir)/voice", atomically: true, encoding: .utf8)
    }

    private func updateETA() {
        guard totalWords > 0, state != .stopped else { etaText = ""; return }
        let remainingWords = totalWords - spokenWords
        let effectiveWPM = TTSEngine.baseWPM * speed
        let remainingSeconds = Int(Double(remainingWords) / effectiveWPM * 60)
        if remainingSeconds < 5 { etaText = "almost done" }
        else if remainingSeconds < 60 { etaText = "~\(remainingSeconds)s left" }
        else { etaText = "~\(remainingSeconds / 60)m \(remainingSeconds % 60)s left" }
    }

    private func wordCountFor(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    func startWatching() {
        let requestFile = "\(Paths.legacyDir)/.request"
        if !FileManager.default.fileExists(atPath: requestFile) {
            FileManager.default.createFile(atPath: requestFile, contents: nil)
        }

        let fd = open(requestFile, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.handleRequest() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.handleRequest() }
        log("File watcher started on \(requestFile)")
    }

    private func handleRequest() {
        let requestFile = "\(Paths.legacyDir)/.request"
        guard let text = try? String(contentsOfFile: requestFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? "".write(toFile: requestFile, atomically: true, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        log("Request received: \(trimmed.prefix(100))...")
        if trimmed == "__STOP__" { stop() }
        else if trimmed == "__TOGGLE__" { toggle() }
        else { speak(text: trimmed) }
    }

    func speak(text: String) {
        stop()
        lastError = nil
        let cleaned = TextCleaner.clean(text)
        guard !cleaned.isEmpty else { return }

        guard FileManager.default.fileExists(atPath: Paths.ttsBin) else {
            lastError = "TTS engine not found at \(Paths.ttsBin)"
            log("ERROR: \(lastError!)")
            return
        }
        guard FileManager.default.fileExists(atPath: "\(Paths.modelDir)/model.onnx") else {
            lastError = "Kokoro model not found at \(Paths.modelDir)"
            log("ERROR: \(lastError!)")
            return
        }

        totalWords = wordCountFor(cleaned)
        spokenWords = 0
        wordCount = totalWords

        let sentences = splitSentences(cleaned)
        guard !sentences.isEmpty else { return }

        totalSentences = sentences.count
        currentIndex = 0
        audioFiles = []
        generateQueue = sentences

        log("Speaking \(totalWords) words in \(totalSentences) chunks")

        DispatchQueue.main.async {
            self.state = .playing
            self.progress = 0
            self.updateETA()
        }

        etaTimer?.invalidate()
        etaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateETA() }
        generateAndPlay()
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if ".!?".contains(char) && current.count > 10 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }

        if sentences.count == 1 && sentences[0].count > 100 {
            let parts = sentences[0].components(separatedBy: CharacterSet(charactersIn: ",;:"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if parts.count > 1 { return parts }
        }
        return sentences
    }

    private func generateAndPlay() {
        guard !generateQueue.isEmpty else { return }
        let sentence = generateQueue.removeFirst()
        let index = totalSentences - generateQueue.count - 1
        let outFile = "\(Paths.configDir)/.chunk_\(index).wav"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.state != .stopped else { return }

            let lengthScale = 1.0 / self.speed
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Paths.ttsBin)
            process.arguments = [
                "--kokoro-model=\(Paths.modelDir)/model.onnx",
                "--kokoro-voices=\(Paths.modelDir)/voices.bin",
                "--kokoro-tokens=\(Paths.modelDir)/tokens.txt",
                "--kokoro-data-dir=\(Paths.modelDir)/espeak-ng-data",
                "--num-threads=2",
                "--sid=\(self.voiceId)",
                "--kokoro-length-scale=\(String(format: "%.2f", lengthScale))",
                "--output-filename=\(outFile)",
                sentence
            ]

            // DYLD_LIBRARY_PATH for the child process to find dylibs
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = Paths.libDir
            process.environment = env

            let errPipe = Pipe()
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            log("TTS generating chunk \(index): \(sentence.prefix(60))...")
            log("TTS bin: \(Paths.ttsBin)")
            log("DYLD_LIBRARY_PATH: \(Paths.libDir)")

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                let msg = "Failed to launch TTS: \(error.localizedDescription)"
                log("ERROR: \(msg)")
                DispatchQueue.main.async { self.lastError = msg }
                return
            }

            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""

            log("TTS exit code: \(process.terminationStatus)")
            if !errStr.isEmpty { log("TTS stderr: \(errStr.prefix(500))") }
            if !outStr.isEmpty { log("TTS stdout: \(outStr.prefix(500))") }

            let wavExists = FileManager.default.fileExists(atPath: outFile)
            log("WAV exists: \(wavExists) at \(outFile)")

            if process.terminationStatus != 0 || !wavExists {
                let msg = "TTS failed (exit \(process.terminationStatus)): \(errStr.prefix(200))"
                log("ERROR: \(msg)")
                DispatchQueue.main.async { self.lastError = msg }
                return
            }

            DispatchQueue.main.async {
                guard self.state != .stopped else { return }
                self.lastError = nil
                self.audioFiles.append(outFile)
                if index == self.currentIndex { self.playNext() }
                if !self.generateQueue.isEmpty { self.generateAndPlay() }
            }
        }
    }

    private func playNext() {
        guard currentIndex < audioFiles.count, state != .stopped else {
            if currentIndex >= totalSentences {
                DispatchQueue.main.async {
                    self.state = .stopped; self.progress = 1.0; self.etaText = "done"
                    self.etaTimer?.invalidate(); self.cleanup()
                    log("Playback complete")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.state == .stopped { self.etaText = "" } }
                }
            }
            return
        }

        let file = audioFiles[currentIndex]
        let sentenceIndex = currentIndex
        log("Playing chunk \(sentenceIndex): \(file)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [file]
            self.player = process
            do {
                try process.run()
            } catch {
                log("afplay failed to launch: \(error)")
                return
            }
            process.waitUntilExit()
            log("afplay exit code: \(process.terminationStatus)")

            DispatchQueue.main.async {
                try? FileManager.default.removeItem(atPath: file)
                let fraction = Double(sentenceIndex + 1) / Double(self.totalSentences)
                self.spokenWords = Int(fraction * Double(self.totalWords))
                self.currentIndex += 1
                self.progress = Double(self.currentIndex) / Double(self.totalSentences)
                self.updateETA()
                if self.state != .stopped { self.playNext() }
            }
        }
    }

    func toggle() {
        switch state {
        case .playing: player?.suspend(); state = .paused
        case .paused: player?.resume(); state = .playing
        case .stopped: break
        }
    }

    func stop() {
        state = .stopped; player?.terminate(); player = nil
        generateQueue = []; etaTimer?.invalidate(); etaText = ""; cleanup()
    }

    private func cleanup() {
        for i in 0..<max(totalSentences, 50) {
            try? FileManager.default.removeItem(atPath: "\(Paths.configDir)/.chunk_\(i).wav")
        }
    }
}

// MARK: - Model Downloader

class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var error: String?
    @Published var isComplete = false

    private let modelURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"
    private var downloadTask: URLSessionDownloadTask?

    func downloadModel() {
        guard !isDownloading, !Paths.modelExists else { return }
        DispatchQueue.main.async {
            self.isDownloading = true
            self.progress = 0
            self.error = nil
        }
        log("Starting model download from \(modelURL)")

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        guard let url = URL(string: modelURL) else { return }
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let pct = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        DispatchQueue.main.async { self.progress = pct }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        log("Model download complete, extracting...")
        let targetDir = Paths.configDir
        let tarPath = "\(targetDir)/kokoro-model.tar.bz2"

        do {
            // Copy downloaded file
            let fm = FileManager.default
            if fm.fileExists(atPath: tarPath) { try fm.removeItem(atPath: tarPath) }
            try fm.copyItem(at: location, to: URL(fileURLWithPath: tarPath))

            // Extract using tar
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["xjf", tarPath, "-C", targetDir]
            try process.run()
            process.waitUntilExit()

            try? fm.removeItem(atPath: tarPath)

            if process.terminationStatus == 0 && Paths.modelExists {
                log("Model extracted successfully to \(Paths.modelDir)")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.isComplete = true
                }
            } else {
                log("Model extraction failed (exit \(process.terminationStatus))")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.error = "Extraction failed"
                }
            }
        } catch {
            log("Model install error: \(error)")
            DispatchQueue.main.async {
                self.isDownloading = false
                self.error = error.localizedDescription
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            log("Model download error: \(error)")
            DispatchQueue.main.async {
                self.isDownloading = false
                self.error = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Sparkle Update Controller

class UpdaterViewModel: ObservableObject {
    static let shared = UpdaterViewModel()

    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var currentVersion: String {
        AppVersion.current
    }
}
