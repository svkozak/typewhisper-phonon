import Foundation
import CryptoKit
import MLX
import MLXAudioCore
import MLXAudioSTT

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
        guard args.count >= 3 else {
            throw PrototypeError.invalid("Usage: PhononSwift MODEL_DIRECTORY AUDIO.wav [RUNS=5] [WEIGHT_AUDIT.json]")
        }
        let directory = URL(fileURLWithPath: args[1])
        let audioURL = URL(fileURLWithPath: args[2])
        let runs = args.count > 3 ? Int(args[3]) ?? 5 : 5
        guard (1...20).contains(runs) else { throw PrototypeError.invalid("RUNS must be 1...20") }
        let start = Date()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("phonon-swift-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        var containerHash = SHA256()
        let handle = try FileHandle(forReadingFrom: directory.appendingPathComponent("model.fermion"))
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { containerHash.update(data: bytes) }
        try handle.close()
        let sha256 = containerHash.finalize().map { String(format: "%02x", $0) }.joined()
        var weights: [String: MLXArray]? = try PhononContainer.read(directory.appendingPathComponent("model.fermion"))
        if args.count > 4 {
            var audit: [String: Any] = [:]
            for (name, value) in weights! {
                let array = value.asType(.float32).asArray(Float.self)
                let hash = array.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
                audit[name] = ["shape": value.shape, "sha256": hash]
            }
            try JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[4]))
        }
        // Use the upstream public loader without patching its model internals.
        // This temporary dense checkpoint is a prototype adapter, not a new model.
        try MLX.save(arrays: weights!, url: scratch.appendingPathComponent("model.safetensors"))
        weights = nil
        Memory.clearCache()
        try FileManager.default.copyItem(at: directory.appendingPathComponent("config.json"), to: scratch.appendingPathComponent("config.json"))
        let conversionSeconds = Date().timeIntervalSince(start)
        let loadStart = Date()
        let model = try ParakeetModel.fromDirectory(scratch, computeDType: .bfloat16)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16000)
        eval(audio)
        let loadPeakMemory = Memory.peakMemory
        Memory.peakMemory = 0
        var latencies: [Double] = [], transcripts: [String] = []
        for _ in 0..<runs {
            let started = Date()
            let output = model.generate(audio: audio)
            Stream.defaultStream.synchronize()
            latencies.append(Date().timeIntervalSince(started))
            transcripts.append(output.text)
        }
        let result: [String: Any] = [
            "engine": "Swift MLX / native Phonon container / dense bfloat16",
            "model_container_sha256": sha256,
            "conversion_seconds": conversionSeconds,
            "model_load_seconds": loadSeconds,
            "audio_seconds": Double(audio.shape[0]) / 16000,
            "decode_seconds": latencies,
            "transcripts": transcripts,
            "mlx_peak_memory_bytes": Memory.peakMemory,
            "mlx_load_peak_memory_bytes": loadPeakMemory,
            "mlx_active_memory_bytes": Memory.activeMemory,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
