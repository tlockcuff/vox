import SwiftUI
import AppKit
import AVFoundation

@main
struct SpeakSelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var engine = TTSEngine.shared
    private var iconTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: "SpeakSel")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ControlsView())

        engine.startWatching()

        // Animate menu bar icon based on state
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private var iconPhase = 0
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        switch engine.state {
        case .playing:
            let icons = ["speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.wave.2.fill"]
            iconPhase = (iconPhase + 1) % icons.count
            button.image = NSImage(systemSymbolName: icons[iconPhase], accessibilityDescription: "Speaking")
        case .paused:
            button.image = NSImage(systemSymbolName: "speaker.badge.exclamationmark", accessibilityDescription: "Paused")
        case .stopped:
            if UpdateChecker.shared.updateAvailable {
                button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Update Available")
            } else {
                button.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: "SpeakSel")
            }
            iconPhase = 0
        }
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

// MARK: - Waveform View

struct WaveformView: View {
    let isActive: Bool
    let isPaused: Bool
    @State private var phase: Double = 0

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
                        // Animated waveform
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let wave1 = sin(Double(i) * 0.4 + t * 4.0) * 0.3
                        let wave2 = sin(Double(i) * 0.7 + t * 2.5) * 0.2
                        let wave3 = cos(Double(i) * 0.3 + t * 3.2) * 0.15
                        let combined = 0.3 + abs(wave1 + wave2 + wave3)
                        height = maxHeight * CGFloat(min(combined, 0.95))
                    } else if isPaused {
                        // Frozen waveform
                        let wave = sin(Double(i) * 0.5) * 0.2
                        height = maxHeight * CGFloat(0.25 + abs(wave))
                    } else {
                        // Flat line
                        height = maxHeight * 0.05
                    }

                    let rect = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )

                    let color: Color = isActive ? (isPaused ? .yellow : .green) : .secondary
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color.opacity(isActive ? 0.8 : 0.3))
                    )
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
            // Waveform
            WaveformView(
                isActive: engine.state != .stopped,
                isPaused: engine.state == .paused
            )
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.2))
            )

            // Status + ETA
            HStack {
                Image(systemName: engine.state == .playing ? "speaker.wave.3.fill" :
                        engine.state == .paused ? "pause.circle.fill" : "speaker.slash")
                    .foregroundColor(engine.state == .playing ? .green :
                        engine.state == .paused ? .yellow : .secondary)
                    .font(.title3)
                Text(engine.state == .playing ? "Speaking" :
                        engine.state == .paused ? "Paused" : "Idle")
                    .font(.headline)
                Spacer()
                if engine.state != .stopped {
                    Text(engine.etaText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            // Progress bar
            if engine.state != .stopped {
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
                    .tint(engine.state == .paused ? .yellow : .green)
            }

            // Transport controls
            HStack(spacing: 20) {
                Button(action: { engine.toggle() }) {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .stopped)

                Button(action: { engine.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .stopped)

                Spacer()

                // Speed
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $engine.speed) {
                        ForEach(speeds, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                    .onChange(of: engine.speed) { _ in
                        engine.saveSpeed()
                    }
                }
            }

            Divider()

            // Voice picker
            HStack {
                Image(systemName: "person.wave.2")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Voice")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Picker("", selection: $engine.voiceId) {
                    ForEach(TTSEngine.voices, id: \.id) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .onChange(of: engine.voiceId) { _ in
                    engine.saveVoice()
                }
            }

            // Word count if available
            if engine.state != .stopped {
                HStack {
                    Text("\(engine.wordCount) words")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("Chunk \(engine.currentIndex + 1)/\(engine.totalSentences)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Update section
            UpdateBannerView()

            // Footer
            HStack {
                Text("v\(UpdateChecker.shared.currentVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit SpeakSel") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Update Banner

struct UpdateBannerView: View {
    @ObservedObject var checker = UpdateChecker.shared

    var body: some View {
        Group {
            if checker.isUpdating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Updating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if checker.updateAvailable, let latest = checker.latestVersion {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Update available: v\(latest)")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Update") {
                        checker.runUpdate()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)))
            } else if checker.isChecking {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Checking for updates...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let error = checker.updateError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        checker.checkForUpdates()
                    }
                    .font(.caption2)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Up to date")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Check") {
                        checker.checkForUpdates()
                    }
                    .font(.caption2)
                }
            }
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

// MARK: - Text Cleanup

struct TextCleaner {
    static func clean(_ text: String) -> String {
        var result = text

        // Remove URLs
        let urlPattern = #"https?://[^\s<>\]\)\"']+"#
        result = result.replacingOccurrences(of: urlPattern, with: "", options: .regularExpression)

        // Remove markdown links but keep text: [text](url) -> text
        let mdLinkPattern = #"\[([^\]]+)\]\([^\)]+\)"#
        result = result.replacingOccurrences(of: mdLinkPattern, with: "$1", options: .regularExpression)

        // Remove markdown images: ![alt](url)
        let mdImgPattern = #"!\[[^\]]*\]\([^\)]+\)"#
        result = result.replacingOccurrences(of: mdImgPattern, with: "", options: .regularExpression)

        // Remove markdown bold/italic markers
        result = result.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)

        // Remove markdown headers (# ## ### etc)
        result = result.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)

        // Remove inline code backticks
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)

        // Remove code blocks
        result = result.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)

        // Remove footnote references like [1], [2], etc.
        result = result.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)

        // Remove HTML tags
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Remove email addresses
        result = result.replacingOccurrences(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, with: "", options: .regularExpression)

        // Remove file paths
        result = result.replacingOccurrences(of: #"(?:/[\w.-]+){2,}"#, with: "", options: .regularExpression)

        // Collapse multiple spaces/newlines
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        // Remove bullet points and list markers
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

    // Average words per minute for Kokoro at 1.0 speed
    private static let baseWPM: Double = 160

    @Published var state: PlaybackState = .stopped
    @Published var progress: Double = 0
    @Published var speed: Double = 1.0
    @Published var voiceId: Int = 5
    @Published var etaText: String = ""
    @Published var wordCount: Int = 0
    @Published var currentIndex: Int = 0
    @Published var totalSentences: Int = 0

    private let speakselDir: String
    private let ttsBin: String
    private let modelDir: String
    private var generateQueue: [String] = []
    private var audioFiles: [String] = []
    private var player: Process?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var startTime: Date?
    private var totalWords: Int = 0
    private var spokenWords: Int = 0
    private var etaTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        speakselDir = "\(home)/.speaksel"
        ttsBin = "\(speakselDir)/bin/sherpa-onnx-offline-tts"
        modelDir = "\(speakselDir)/kokoro-en-v0_19"
        loadConfig()
    }

    func loadConfig() {
        if let v = try? String(contentsOfFile: "\(speakselDir)/voice", encoding: .utf8) {
            voiceId = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5
        }
        if let s = try? String(contentsOfFile: "\(speakselDir)/speed", encoding: .utf8) {
            speed = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
        }
    }

    func saveSpeed() {
        try? String(speed).write(toFile: "\(speakselDir)/speed", atomically: true, encoding: .utf8)
    }

    func saveVoice() {
        try? String(voiceId).write(toFile: "\(speakselDir)/voice", atomically: true, encoding: .utf8)
    }

    // MARK: - ETA Calculation

    private func updateETA() {
        guard totalWords > 0, state != .stopped else {
            etaText = ""
            return
        }

        let remainingWords = totalWords - spokenWords
        let effectiveWPM = TTSEngine.baseWPM * speed
        let remainingSeconds = Int(Double(remainingWords) / effectiveWPM * 60)

        if remainingSeconds < 5 {
            etaText = "almost done"
        } else if remainingSeconds < 60 {
            etaText = "~\(remainingSeconds)s left"
        } else {
            let min = remainingSeconds / 60
            let sec = remainingSeconds % 60
            etaText = "~\(min)m \(sec)s left"
        }
    }

    private func wordCountFor(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - File Watching

    func startWatching() {
        let requestFile = "\(speakselDir)/.request"
        if !FileManager.default.fileExists(atPath: requestFile) {
            FileManager.default.createFile(atPath: requestFile, contents: nil)
        }

        let fd = open(requestFile, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleRequest()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.handleRequest()
        }
    }

    private func handleRequest() {
        let requestFile = "\(speakselDir)/.request"
        guard let text = try? String(contentsOfFile: requestFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? "".write(toFile: requestFile, atomically: true, encoding: .utf8)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "__STOP__" {
            stop()
        } else if trimmed == "__TOGGLE__" {
            toggle()
        } else {
            speak(text: trimmed)
        }
    }

    // MARK: - Speak

    func speak(text: String) {
        stop()

        // Clean the text first
        let cleaned = TextCleaner.clean(text)
        guard !cleaned.isEmpty else { return }

        totalWords = wordCountFor(cleaned)
        spokenWords = 0
        wordCount = totalWords

        let sentences = splitSentences(cleaned)
        guard !sentences.isEmpty else { return }

        totalSentences = sentences.count
        currentIndex = 0
        audioFiles = []
        generateQueue = sentences
        startTime = Date()

        DispatchQueue.main.async {
            self.state = .playing
            self.progress = 0
            self.updateETA()
        }

        // Start ETA timer
        etaTimer?.invalidate()
        etaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateETA()
        }

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
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count > 1 { return parts }
        }

        return sentences
    }

    // MARK: - Generate & Play Pipeline

    private func generateAndPlay() {
        guard !generateQueue.isEmpty else { return }

        let sentence = generateQueue.removeFirst()
        let index = totalSentences - generateQueue.count - 1
        let outFile = "\(speakselDir)/.chunk_\(index).wav"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.state != .stopped else { return }

            let lengthScale = 1.0 / self.speed
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.ttsBin)
            process.arguments = [
                "--kokoro-model=\(self.modelDir)/model.onnx",
                "--kokoro-voices=\(self.modelDir)/voices.bin",
                "--kokoro-tokens=\(self.modelDir)/tokens.txt",
                "--kokoro-data-dir=\(self.modelDir)/espeak-ng-data",
                "--num-threads=2",
                "--sid=\(self.voiceId)",
                "--kokoro-length-scale=\(String(format: "%.2f", lengthScale))",
                "--output-filename=\(outFile)",
                sentence
            ]
            process.environment = [
                "DYLD_LIBRARY_PATH": "\(self.speakselDir)/bin",
                "PATH": "/usr/bin:/bin"
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch { return }

            DispatchQueue.main.async {
                guard self.state != .stopped else { return }
                self.audioFiles.append(outFile)

                if index == self.currentIndex {
                    self.playNext()
                }
                if !self.generateQueue.isEmpty {
                    self.generateAndPlay()
                }
            }
        }
    }

    private func playNext() {
        guard currentIndex < audioFiles.count, state != .stopped else {
            if currentIndex >= totalSentences {
                DispatchQueue.main.async {
                    self.state = .stopped
                    self.progress = 1.0
                    self.etaText = "done"
                    self.etaTimer?.invalidate()
                    self.cleanup()
                    // Reset eta after a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.state == .stopped { self.etaText = "" }
                    }
                }
            }
            return
        }

        let file = audioFiles[currentIndex]
        let sentenceIndex = currentIndex

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [file]
            self.player = process

            do { try process.run() } catch { return }
            process.waitUntilExit()

            DispatchQueue.main.async {
                try? FileManager.default.removeItem(atPath: file)

                // Update spoken word count (estimate from sentence ratio)
                let fraction = Double(sentenceIndex + 1) / Double(self.totalSentences)
                self.spokenWords = Int(fraction * Double(self.totalWords))

                self.currentIndex += 1
                self.progress = Double(self.currentIndex) / Double(self.totalSentences)
                self.updateETA()

                if self.state != .stopped {
                    self.playNext()
                }
            }
        }
    }

    // MARK: - Controls

    func toggle() {
        switch state {
        case .playing:
            player?.suspend()
            state = .paused
        case .paused:
            player?.resume()
            state = .playing
        case .stopped:
            break
        }
    }

    func stop() {
        state = .stopped
        player?.terminate()
        player = nil
        generateQueue = []
        etaTimer?.invalidate()
        etaText = ""
        cleanup()
    }

    private func cleanup() {
        for i in 0..<max(totalSentences, 50) {
            try? FileManager.default.removeItem(atPath: "\(speakselDir)/.chunk_\(i).wav")
        }
    }
}

// MARK: - Update Checker

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateError: String?

    let currentVersion: String
    private let speakselDir: String
    private let repo = "tlockcuff/speaksel"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        speakselDir = "\(home)/.speaksel"
        let versionFile = "\(speakselDir)/.version"
        if let v = try? String(contentsOfFile: versionFile, encoding: .utf8) {
            currentVersion = v.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
        } else {
            currentVersion = "0.0.0"
        }

        // Check on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.checkForUpdates()
        }

        // Check every 6 hours
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        guard !isChecking, !isUpdating else { return }
        isChecking = true
        updateError = nil

        // Use GitHub API to get latest release
        let urlStr = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlStr) else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        // Try to use gh token if available
        if let token = getGHToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false

                if let error = error {
                    self.updateError = "Network error"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.updateError = "Could not check"
                    return
                }

                let latest = tagName.replacingOccurrences(of: "v", with: "")
                self.latestVersion = latest
                self.updateAvailable = self.isNewer(latest, than: self.currentVersion)
            }
        }.resume()
    }

    private func getGHToken() -> String? {
        // Check gh CLI config
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gh/hosts.yml").path
        if let config = try? String(contentsOfFile: configPath, encoding: .utf8) {
            // Simple parse for oauth_token
            for line in config.components(separatedBy: "\n") {
                if line.contains("oauth_token:") {
                    return line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        // Check env
        if let token = ProcessInfo.processInfo.environment["GH_TOKEN"] {
            return token
        }
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
            return token
        }

        return nil
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }

    func runUpdate() {
        isUpdating = true
        updateError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let updateScript = "\(self.speakselDir)/update.sh"
            guard FileManager.default.fileExists(atPath: updateScript) else {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.updateError = "update.sh not found"
                }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [updateScript]
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.updateError = "Update failed"
                }
                return
            }

            DispatchQueue.main.async {
                self.isUpdating = false
                if process.terminationStatus == 0 {
                    self.updateAvailable = false
                    self.updateError = nil
                    // The update script restarts the app, but just in case:
                    // Re-check version
                    let versionFile = "\(self.speakselDir)/.version"
                    if let v = try? String(contentsOfFile: versionFile, encoding: .utf8) {
                        // App will be restarted by the installer
                    }
                } else {
                    self.updateError = "Update failed (exit \(process.terminationStatus))"
                }
            }
        }
    }
}
