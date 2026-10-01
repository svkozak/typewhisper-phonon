import Foundation
import TypeWhisperPluginSDK
@main struct BundleTest {
 static func main() async throws {
  let bundle = Bundle(path: CommandLine.arguments[1])!
  try bundle.loadAndReturnError()
  guard let cls = bundle.principalClass as? any TypeWhisperPlugin.Type else { fatalError("Principal class does not conform to SDK") }
  guard let plugin = cls.init() as? any TranscriptionEnginePlugin else { fatalError("No transcription engine") }

        let host = try makeTestHost()
        plugin.activate(host: host)
        defer { plugin.deactivate(); cleanupTestHost(host) }
        try await waitForPlugin(plugin)
  let wav = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
  let start = ContinuousClock.now
  let result = try await plugin.transcribe(audio: AudioData(samples: [], wavData: wav, duration: 0), language: "en", translate: false, prompt: nil)
  print("Bundle loaded: \(type(of: plugin)); latency: \(start.duration(to: .now))")
  print(result.text)
 }
}
