import Foundation
import CryptoKit

@main struct RuntimeTest {
    static func main() async throws {
        let data = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = URL(fileURLWithPath: RuntimeLocation.directory).appendingPathComponent("Resources/runtime-manifest.json")
        let setup = PhononRuntime(manifestURL: manifest, dataDirectory: data)
        let runtime = try await setup.prepare { print($0) }
        print("PASS: runtime downloaded, verified, extracted, and validated at \(runtime.path)")
        let reused = try await setup.prepare { _ in fatalError("Warm setup must not download") }
        guard reused.path == runtime.path else { fatalError("Runtime not reused") }
        print("PASS: completed runtime is reused without downloads")
        var badManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        var asset = (badManifest["assets"] as! [[String: Any]])[1]
        asset["sha256"] = String(repeating: "0", count: 64)
        badManifest["assets"] = [asset]
        badManifest["version"] = "checksum-test"
        let badFile = data.appendingPathComponent("bad-manifest.json")
        try JSONSerialization.data(withJSONObject: badManifest).write(to: badFile)
        defer { try? FileManager.default.removeItem(at: badFile) }
        let badSetup = PhononRuntime(manifestURL: badFile, dataDirectory: data)
        do {
            _ = try await badSetup.prepare { _ in }
            throw PhononError(message: "Invalid checksum was accepted")
        } catch let error as PhononError {
            guard error.message.contains("Checksum verification failed") else { throw error }
        }
        let folders = try FileManager.default.contentsOfDirectory(at: data.appendingPathComponent("Runtime"), includingPropertiesForKeys: nil)
        guard !folders.contains(where: { $0.lastPathComponent.hasPrefix(".install-") || $0.lastPathComponent == "checksum-test" }) else {
            throw PhononError(message: "Failed setup left an installable runtime")
        }
        print("PASS: checksum rejection removes incomplete setup")
        let root = URL(fileURLWithPath: RuntimeLocation.directory)
        let server = PhononServer(runtime: runtime, helper: root.appendingPathComponent("scripts/managed-server.py"), dataDirectory: data)
        server.start()
        defer { server.stop() }
        let deadline = Date().addingTimeInterval(600)
        while server.status != .ready {
            if case .failed(let message) = server.status { throw PhononError(message: message) }
            guard Date() < deadline else { throw PhononError(message: "Fresh model readiness timeout") }
            try await Task.sleep(for: .milliseconds(250))
        }
        let wav = try Data(contentsOf: root.appendingPathComponent("build/sample.wav"))
        let result = try await PhononPlugin.transcribeWAV(wav, connection: server.activeConnection())
        guard result.text == "This is a local speech recognition test. Please schedule the project review for Friday afternoon." else { throw PhononError(message: "Unexpected transcript: " + result.text) }
        print("PASS: provisioned runtime downloads the model into plugin data and transcribes correctly")
    }
}
