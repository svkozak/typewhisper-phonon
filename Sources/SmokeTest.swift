import Foundation
import TypeWhisperPluginSDK
@main struct SmokeTest {
    static func main() async throws {
        let wav = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let plugin = PhononPlugin()
        let audio = AudioData(samples: [], wavData: wav, duration: 0)
        let start = ContinuousClock.now
        let result = try await plugin.transcribe(audio: audio, language: "en", translate: false, prompt: nil)
        print("Latency: \(start.duration(to: .now))")
        print(result.text)
        do { _ = try await plugin.transcribe(audio: audio, language: "en", translate: true, prompt: nil); fatalError("Translation accepted") }
        catch is PhononError { print("Translation rejection passed") }
        do { _ = try await plugin.transcribe(audio: AudioData(samples: [], wavData: Data(), duration: 0), language: "en", translate: false, prompt: nil); fatalError("Invalid WAV accepted") }
        catch is PhononError { print("Invalid WAV rejection passed") }
    }
}
