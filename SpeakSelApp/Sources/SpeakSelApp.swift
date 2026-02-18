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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var engine = TTSEngine.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "SpeakSel")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ControlsView())

        // Watch for speak requests via file
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

struct ControlsView: View {
    @ObservedObject var engine = TTSEngine.shared
    
    let speeds: [(String, Double)] = [
        ("0.5x", 0.5), ("0.75x", 0.75), ("1x", 1.0),
        ("1.25x", 1.25), ("1.5x", 1.5), ("2x", 2.0)
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Status
            HStack {
                Image(systemName: engine.state == .playing ? "speaker.wave.3.fill" :
                        engine.state == .paused ? "pause.circle.fill" : "speaker.slash")
                    .foregroundColor(engine.state == .playing ? .green :
                        engine.state == .paused ? .yellow : .secondary)
                    .font(.title2)
                Text(engine.state == .playing ? "Speaking..." :
                        engine.state == .paused ? "Paused" : "Idle")
                    .font(.headline)
                Spacer()
            }

            // Progress (approximate)
            if engine.state != .stopped {
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
            }

            // Controls
            HStack(spacing: 16) {
                Button(action: { engine.toggle() }) {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .stopped)

                Button(action: { engine.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .stopped)

                Spacer()

                // Speed selector
                Picker("", selection: $engine.speed) {
                    ForEach(speeds, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .onChange(of: engine.speed) { _ in
                    engine.saveSpeed()
                }
            }

            // Voice
            HStack {
                Text("Voice:")
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

            // Quit
            HStack {
                Spacer()
                Button("Quit SpeakSel") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct Voice: Identifiable {
    let id: Int
    let name: String
}

enum PlaybackState {
    case stopped, playing, paused
}

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

    @Published var state: PlaybackState = .stopped
    @Published var progress: Double = 0
    @Published var speed: Double = 1.0
    @Published var voiceId: Int = 5

    private let speakselDir: String
    private let ttsBin: String
    private let modelDir: String
    private var playProcess: Process?
    private var generateQueue: [String] = []
    private var isGenerating = false
    private var audioFiles: [String] = []
    private var currentIndex = 0
    private var totalSentences = 0
    private var player: Process?
    private var fileWatcher: DispatchSourceFileSystemObject?

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

    func startWatching() {
        // Watch for .request file (written by the shell script / Quick Action)
        let requestFile = "\(speakselDir)/.request"
        // Create file if it doesn't exist
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
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileWatcher = source

        // Also poll periodically as backup
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.handleRequest()
        }
    }

    private func handleRequest() {
        let requestFile = "\(speakselDir)/.request"
        guard let text = try? String(contentsOfFile: requestFile, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        // Clear the request file immediately
        try? "".write(toFile: requestFile, atomically: true, encoding: .utf8)
        speak(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func speak(text: String) {
        stop()

        // Split into sentences for streaming
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return }

        totalSentences = sentences.count
        currentIndex = 0
        audioFiles = []
        generateQueue = sentences

        DispatchQueue.main.async {
            self.state = .playing
            self.progress = 0
        }

        // Start generating sentences - pipeline style
        generateAndPlay()
    }

    private func splitSentences(_ text: String) -> [String] {
        // Split on sentence boundaries but keep chunks reasonable
        var sentences: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if ".!?".contains(char) && current.count > 10 {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }

        // If only one long sentence, split on commas/semicolons for faster first audio
        if sentences.count == 1 && sentences[0].count > 100 {
            let parts = sentences[0].components(separatedBy: CharacterSet(charactersIn: ",;:"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return parts
            }
        }

        return sentences
    }

    private func generateAndPlay() {
        guard !generateQueue.isEmpty else { return }

        let sentence = generateQueue.removeFirst()
        let index = totalSentences - generateQueue.count - 1
        let outFile = "\(speakselDir)/.chunk_\(index).wav"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

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
            } catch {
                return
            }

            DispatchQueue.main.async {
                self.audioFiles.append(outFile)

                // If this is the first chunk, start playing immediately
                if index == self.currentIndex {
                    self.playNext()
                }

                // Generate next sentence in pipeline
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
                    self.cleanup()
                }
            }
            return
        }

        let file = audioFiles[currentIndex]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [file]

            self.player = process

            do {
                try process.run()
            } catch {
                return
            }

            process.waitUntilExit()

            DispatchQueue.main.async {
                // Clean up played file
                try? FileManager.default.removeItem(atPath: file)

                self.currentIndex += 1
                self.progress = Double(self.currentIndex) / Double(self.totalSentences)

                if self.state != .stopped {
                    self.playNext()
                }
            }
        }
    }

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
        cleanup()
    }

    private func cleanup() {
        // Remove chunk files
        for i in 0..<totalSentences {
            try? FileManager.default.removeItem(atPath: "\(speakselDir)/.chunk_\(i).wav")
        }
    }
}
