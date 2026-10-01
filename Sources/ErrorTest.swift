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
  try await expect("inactive plugin", contains: "Enable Phonon", audio: valid)
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("phonon-http-test-" + UUID().uuidString)
  let python = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHONON_TEST_PYTHON"] ?? "/usr/bin/python3")
  let server = PhononServer(executable: python, dataDirectory: folder,
                            arguments: ["-I", "-B", "-u", root.appendingPathComponent("scripts/mock-error-server.py").path])
  server.start()
  defer { server.stop(); try? FileManager.default.removeItem(at: folder) }
  let deadline = Date().addingTimeInterval(10)
  while server.status != .ready {
   guard Date() < deadline else { throw PhononError(message: "Mock readiness timeout") }
   try await Task.sleep(for: .milliseconds(100))
  }
  let connection = try server.activeConnection()
  for expected in ["HTTP 503", "invalid transcript"] {
   do {
    _ = try await PhononPlugin.transcribeWAV(wav, connection: connection)
    throw PhononError(message: "Mock unexpectedly succeeded")
   } catch let error as PhononError {
    guard error.message.contains(expected) else { throw error }
    print("PASS: " + expected)
   }
  }
  let result = try await PhononPlugin.transcribeWAV(wav, connection: connection)
  guard result.text == "Mock transcript" else { throw PhononError(message: "Wrong mock transcript") }
  print("PASS: WAV multipart, private authentication, and valid JSON")

 }
}
