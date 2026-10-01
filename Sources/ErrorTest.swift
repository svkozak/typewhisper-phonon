import Foundation
import TypeWhisperPluginSDK
@main struct ErrorTest {
 static func main() async throws {
  let plugin = PhononPlugin()
  let wav = PluginWavEncoder.encode([0, 0, 0])
  let valid = AudioData(samples: [], wavData: wav, duration: 0)
  func expect(_ label: String, contains: String, audio: AudioData, language: String? = "en", translate: Bool = false) async throws {
   do { _ = try await plugin.transcribe(audio: audio, language: language, translate: translate, prompt: "ignored hint"); throw NSError(domain: "Test unexpectedly succeeded", code: 1) }
   catch let error as PhononError {
    guard error.message.contains(contains) else { throw NSError(domain: "Unexpected error: \(error.message)", code: 2) }
    print("PASS: \(label)")
   }
  }
  try await expect("translation", contains: "translation", audio: valid, translate: true)
  try await expect("non-English", contains: "English only", audio: valid, language: "fr")
  try await expect("short/invalid WAV", contains: "Expected a WAV", audio: AudioData(samples: [], wavData: Data(), duration: 0))
  var oversized = wav; oversized.append(Data(count: 31_000_000))
  try await expect("oversized WAV", contains: "too large", audio: AudioData(samples: [], wavData: oversized, duration: 0))
  if CommandLine.arguments.contains("--mock") {
   try await expect("HTTP failure", contains: "HTTP 503", audio: valid)
   try await expect("malformed JSON", contains: "invalid transcript", audio: valid)
   let result = try await plugin.transcribe(audio: valid, language: nil, translate: false, prompt: "ignored hint")
   guard result.text == "Mock transcript" else { fatalError("Unexpected transcript") }
   print("PASS: valid JSON response")
  } else {
   try await expect("server unavailable", contains: "Start scripts/serve.sh", audio: valid)
  }
 }
}
