import Foundation
import CZstd

enum PrototypeError: Error { case invalid(String) }

@main struct ModelStoreTest {
    static func main() throws {
        let archive = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phonon-model-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let digest = try ModelStore.hash(archive)
        precondition(digest == ModelStore.archiveHash)
        let tar = root.appendingPathComponent("model.tar")
        precondition(phonon_decompress(archive.path, tar.path, 180_000_000) == 0)
        let model = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: false)
        try ModelStore.extract(tar, to: model)
        precondition(ModelStore.valid(model))
        try Data("damaged".utf8).write(to: model.appendingPathComponent("config.json"))
        precondition(!ModelStore.valid(model))
        print("PASS: pinned archive, native decompression, extraction, model hashes, corrupt cache detection")
        let rejected = root.appendingPathComponent("rejected.tar")
        precondition(phonon_decompress(archive.path, rejected.path, 1024) != 0)
        precondition(!FileManager.default.fileExists(atPath: rejected.path))
        let compressed = try Data(contentsOf: archive)
        let truncated = root.appendingPathComponent("truncated.zst")
        try compressed.prefix(1024).write(to: truncated)
        precondition(phonon_decompress(truncated.path, rejected.path, 180_000_000) != 0)
        print("PASS: decompression size bound and truncated frame rejection")
        let bytes = try Data(contentsOf: tar)
        func reject(_ altered: Data) throws {
            try altered.write(to: rejected)
            let output = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            do { try ModelStore.extract(rejected, to: output); fatalError("Unsafe archive accepted") }
            catch is PrototypeError {}
        }
        var unsafe = bytes
        unsafe.replaceSubrange(0..<100, with: Data("../escape".utf8) + Data(repeating: 0, count: 91))
        try reject(unsafe)
        unsafe = bytes; unsafe[156] = 50
        try reject(unsafe)
        unsafe = bytes; unsafe[148] ^= 1
        try reject(unsafe)
        try reject(bytes.prefix(600))
        print("PASS: archive traversal, links, invalid checksums, and truncated entry rejection")
    }
}
