import Foundation
import SwiftUI
import AppKit
import TypeWhisperPluginSDK

struct PhononError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@objc(PhononPlugin)
public final class PhononPlugin: NSObject, TranscriptionEnginePlugin, PluginSettingsActivityReporting, @unchecked Sendable {
    public static let pluginId = "local.typewhisper.phonon"
    public static var pluginName: String {
        Bundle(for: PhononPlugin.self).url(forResource: "PhononSwift", withExtension: nil, subdirectory: "Native") == nil ? "Phonon Local" : "Phonon Local (Swift)"
    }
    public override required init() { super.init() }
    // The activation lock protects the controller and host reference together.
    private let activationLock = NSLock()
    private var server: PhononServer?
    private var host: (any HostServices)?

    public func activate(host: HostServices) {
        activationLock.withLock {
            server?.stop()
            self.host = host
            server = makeServer(host: host)
            server?.start()
        }
    }
    public func deactivate() {
        activationLock.withLock {
            server?.stop()
            server = nil
            host = nil
        }
    }
    deinit { deactivate() }

    private func makeServer(host: any HostServices) -> PhononServer {
        let bundle = Bundle(for: PhononPlugin.self)
        if let executable = bundle.url(forResource: "PhononSwift", withExtension: nil, subdirectory: "Native") {
            return PhononServer(runtime: executable.deletingLastPathComponent(), helper: executable,
                                dataDirectory: host.pluginDataDirectory, nativeExecutable: executable) {
                Task { @MainActor in host.notifyCapabilitiesChanged() }
            }
        }
        let runtime = host.pluginDataDirectory.appendingPathComponent("Runtime")
        let helper = bundle.url(forResource: "managed-server", withExtension: "py")
            ?? URL(fileURLWithPath: RuntimeLocation.directory).appendingPathComponent("scripts/managed-server.py")
        let manifest = bundle.url(forResource: "runtime-manifest", withExtension: "json")
            ?? URL(fileURLWithPath: RuntimeLocation.directory).appendingPathComponent("Resources/runtime-manifest.json")
        let setup = PhononRuntime(manifestURL: manifest, dataDirectory: host.pluginDataDirectory)
        return PhononServer(runtime: runtime, helper: helper, dataDirectory: host.pluginDataDirectory, setup: setup) {
            Task { @MainActor in host.notifyCapabilitiesChanged() }
        }
    }

    var serverStatus: PhononServerState {
        activationLock.withLock { server?.status ?? .stopped }
    }
    public var currentSettingsActivity: PluginSettingsActivity? {
        switch serverStatus {
        case .ready, .stopped: return nil
        case .starting: return PluginSettingsActivity(message: PhononServerState.starting.message)
        case .installing(let message): return PluginSettingsActivity(message: message)
        case .failed(let message): return PluginSettingsActivity(message: message, isError: true)
        }
    }
    func restartServer() {
        activationLock.withLock {
            guard let host else { return }
            server?.stop()
            server = makeServer(host: host)
            server?.start()
        }
    }
    @MainActor func showLogs() {
        if let folder = activationLock.withLock({ host?.pluginDataDirectory }) {
            NSWorkspace.shared.open(folder)
        }
    }
    public let providerId = "phonon-local"
    public var providerDisplayName: String { Self.pluginName.contains("Swift") ? "Phonon-2 (Swift / MLX)" : "Phonon-2 (Local)" }
    public var isConfigured: Bool { serverStatus == .ready }
    public var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: "phonon-2", displayName: "Phonon-2", sizeDescription: "164 MB download", languageCount: 1)]
    }
    public var selectedModelId: String? { "phonon-2" }
    public func selectModel(_ modelId: String) {}
    public let supportsTranslation = false
    public let supportsStreaming = false
    public let supportedLanguages = ["en"]
    @MainActor public var settingsView: AnyView? {
        AnyView(PhononSettingsView(plugin: self))
    }
    public func transcribe(audio: AudioData, language: String?, translate: Bool, prompt: String?) async throws -> PluginTranscriptionResult {
        guard !translate else { throw PhononError(message: "Phonon prototype does not support translation.") }
        guard language == nil || ["en", "english", "auto"].contains(language!.lowercased()) else {
            throw PhononError(message: "This prototype supports English only. Select English or automatic language.")
        }
        guard audio.wavData.count >= 44, audio.wavData.prefix(4) == Data("RIFF".utf8), audio.wavData[8..<12] == Data("WAVE".utf8) else {
            throw PhononError(message: "Expected a WAV recording.")
        }
        guard audio.wavData.count < 31_000_000 else { throw PhononError(message: "Recording is too large. Split into shorter clips.") }
        let connection = try activationLock.withLock {
            guard let server else { throw PhononError(message: "Enable Phonon Local before dictating.") }
            return try server.activeConnection()
        }
        return try await Self.transcribeWAV(audio.wavData, connection: connection)
    }

    static func transcribeWAV(_ wavData: Data, connection: PhononConnection) async throws -> PluginTranscriptionResult {
        let boundary = "Phonon-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in [("model", "phonon-2"), ("response_format", "json")] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: connection.transcriptionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .cannotConnectToHost {
            throw PhononError(message: "Phonon server is restarting or unavailable. Retry shortly, or restart Phonon in its settings.")
        }
        guard let http = response as? HTTPURLResponse else { throw PhononError(message: "Invalid server response.") }
        guard http.statusCode == 200 else {
            throw PhononError(message: "Phonon HTTP \(http.statusCode): \(String(decoding: data.prefix(1024), as: UTF8.self))")
        }
        struct Transcript: Decodable { let text: String }
        guard let transcript = try? JSONDecoder().decode(Transcript.self, from: data) else {
            throw PhononError(message: "Phonon returned an invalid transcript response.")
        }
        return PluginTranscriptionResult(text: transcript.text, detectedLanguage: "en")
    }
}

@MainActor
private struct PhononSettingsView: View {
    let plugin: PhononPlugin
    @State private var status: PhononServerState = .stopped

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phonon-2").font(.headline)
            Text(status.message)
                .foregroundStyle(isError ? Color.red : Color.primary)
            if isBusy { ProgressView().controlSize(.small) }
            Text("The local server starts automatically when this plugin is enabled. It stops when the plugin is disabled or TypeWhisper exits.")
            Text("Phonon-2 downloads once (164 MB). Dictation then runs locally with Swift and MLX.").foregroundStyle(.secondary)
            Text("English only. Translation and live streaming are unavailable.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Restart Phonon") { plugin.restartServer(); status = plugin.serverStatus }
                Button("Show Logs") { plugin.showLogs() }
            }
        }
        .padding()
        .task {
            while !Task.isCancelled {
                status = plugin.serverStatus
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    private var isBusy: Bool {
        switch status { case .starting, .installing: true; default: false }
    }

    private var isError: Bool {
        if case .failed = status { return true }
        return false
    }
}
