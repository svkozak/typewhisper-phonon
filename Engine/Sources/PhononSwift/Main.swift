import Foundation

@main struct PhononSwift {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("PhononSwift: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        let args = CommandLine.arguments
        if args.count == 2, args[1] == "--serve" {
            try NativeServer.run()
            return
        }
        guard (3...4).contains(args.count) else {
            throw PrototypeError.invalid("Usage: PhononSwift CACHE_DIRECTORY AUDIO.wav [RUNS=5]")
        }
        let cache = URL(fileURLWithPath: args[1])
        let audioURL = URL(fileURLWithPath: args[2])
        let runs = args.count > 3 ? Int(args[3]) ?? 5 : 5
        guard (1...20).contains(runs) else { throw PrototypeError.invalid("RUNS must be 1...20") }
        let samples = try NativeServer.decodeWAV(Data(contentsOf: audioURL))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let status = cache.appendingPathComponent("cli-\(UUID().uuidString).status")
        defer { try? FileManager.default.removeItem(at: status) }
        let start = Date()
        let model = try CoreMLEngine.load(cache: cache, statusFile: status)
        let loadSeconds = Date().timeIntervalSince(start)
        var latencies: [Double] = [], transcripts: [String] = []
        for _ in 0..<runs {
            let started = Date()
            let text = try CoreMLEngine.transcribe(samples, using: model)
            latencies.append(Date().timeIntervalSince(started))
            transcripts.append(text)
        }
        let result: [String: Any] = [
            "engine": "Swift Core ML / CPU and Neural Engine",
            "model_revision": ModelStore.revision,
            "model_load_seconds": loadSeconds,
            "coreml_compile_seconds": model.compileSeconds,
            "audio_seconds": Double(samples.count) / 16000,
            "decode_seconds": latencies,
            "transcripts": transcripts,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
