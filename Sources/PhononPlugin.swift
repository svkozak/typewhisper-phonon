import Foundation
import SwiftUI
import TypeWhisperPluginSDK

struct PhononError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@objc(PhononPlugin)
public final class PhononPlugin: NSObject, TranscriptionEnginePlugin, @unchecked Sendable {
    public static let pluginId = "local.typewhisper.phonon"
    public static let pluginName = "Phonon Local"
    public override required init() { super.init() }
    public func activate(host: HostServices) {}
    public func deactivate() {}
    public let providerId = "phonon-local"
    public let providerDisplayName = "Phonon-2 (Local)"
    public var isConfigured: Bool { true }
    public var transcriptionModels: [PluginModelInfo] {
        [PluginModelInfo(id: "phonon-2", displayName: "Phonon-2", sizeDescription: "164 MB download", languageCount: 1)]
    }
    public var selectedModelId: String? { "phonon-2" }
    public func selectModel(_ modelId: String) {}
    public let supportsTranslation = false
    public let supportsStreaming = false
    public let supportedLanguages = ["en"]
    @MainActor public var settingsView: AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 12) {
            Text("Phonon-2 · English batch dictation").font(.headline)
            Text("Run scripts/serve.sh from the prototype repository before dictating.")
            Text("Endpoint: http://127.0.0.1:8010/v1/audio/transcriptions")
            Text("WAV only. No API key, translation, streaming, or prompt hints. Stop the server with Control-C.")
        }.padding())
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
        let boundary = "Phonon-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in [("model", "phonon-2"), ("response_format", "json")] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio.wavData)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8010/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
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
            throw PhononError(message: "Phonon server is unavailable. Start scripts/serve.sh, then retry.")
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
