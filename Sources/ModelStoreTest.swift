import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String = "Model store check failed") throws {
    guard condition() else { throw PrototypeError.invalid(message) }
}

@main struct ModelStoreTest {
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        try require(ModelStore.valid(source), "Supply a verified Core ML model directory")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phonon-model-test-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let model = ModelStore.directory(cache: cache)
        try fm.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: model)
        try require(ModelStore.valid(model))
        print("PASS: pinned Core ML files, byte counts, and SHA-256 checksums")
        for artifact in ModelStore.artifacts {
            let file = model.appendingPathComponent(artifact.path)
            let saved = root.appendingPathComponent("saved")
            try fm.moveItem(at: file, to: saved)
            try require(!ModelStore.valid(model), "Missing model file accepted")
            try fm.copyItem(at: saved, to: file)
            let handle = try FileHandle(forWritingTo: file)
            try handle.write(contentsOf: Data([0xff]))
            try handle.close()
            try require(!ModelStore.valid(model), "Corrupt model file accepted")
            try fm.removeItem(at: file)
            try Data([0]).write(to: file)
            try require(!ModelStore.valid(model), "Truncated model file accepted")
            try fm.removeItem(at: file)
            try fm.createSymbolicLink(at: file, withDestinationURL: saved)
            try require(!ModelStore.valid(model), "Linked model file accepted")
            try fm.removeItem(at: file)
            try fm.moveItem(at: saved, to: file)
        }
        print("PASS: missing, corrupt, truncated, and linked model inputs rejected")
        let package = model.appendingPathComponent(ModelStore.packageName)
        let saved = root.appendingPathComponent("package")
        try fm.moveItem(at: package, to: saved)
        try fm.createSymbolicLink(at: package, withDestinationURL: saved)
        try require(!ModelStore.valid(model), "Linked package directory accepted")
        try fm.removeItem(at: package)
        try fm.moveItem(at: saved, to: package)
        print("PASS: linked package directory rejected")
        let manifest = ModelStore.artifacts[0]
        let status = root.appendingPathComponent("status.json")
        do {
            try ModelStore.download(ModelStore.Artifact(path: manifest.path, bytes: 1, sha256: manifest.sha256),
                                    to: root.appendingPathComponent("oversized"), downloaded: 0, statusFile: status)
            throw NSError(domain: "Oversized response accepted", code: 1)
        } catch is PrototypeError {}
        try require(!fm.fileExists(atPath: root.appendingPathComponent("oversized").path))
        print("PASS: oversized download rejected before cache publication")
        try require(ModelStore.compiledValid(source), "Supply a compiled Core ML cache")
        try require(ModelStore.compiledValid(model), "Copied compiled cache is invalid: \(model.path)")
        let compiled = model.appendingPathComponent(ModelStore.compiledName)
        let extra = compiled.appendingPathComponent("unexpected")
        try Data([1]).write(to: extra)
        try require(!ModelStore.compiledValid(model), "Unexpected compiled file accepted")
        try fm.removeItem(at: extra)
        let inventory = fm.enumerator(at: compiled, includingPropertiesForKeys: [.isRegularFileKey])!
        let file = inventory.compactMap { $0 as? URL }.first { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && ((try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.int64Value ?? 0) > 0 }!
        let handle = try FileHandle(forUpdating: file)
        let first = try handle.read(upToCount: 1)!
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data([first[0] ^ 1]))
        try handle.close()
        try require(!ModelStore.compiledValid(model), "Corrupt compiled file accepted")
        print("PASS: compiled inventory rejects unexpected files and changed content")
        let stale = model.appendingPathComponent(".native-compile-interrupted")
        try fm.createDirectory(at: stale, withIntermediateDirectories: false)
        let rebuilt = try ModelStore.prepare(cache: cache, statusFile: status)
        try require(ModelStore.compiledValid(rebuilt), "Compiled cache recovery failed")
        try require(!fm.fileExists(atPath: stale.path), "Interrupted compilation was not reclaimed")
        let entries = try fm.contentsOfDirectory(atPath: model.path)
        try require(entries.contains { $0.hasPrefix("compiled-backup-") }, "Previous compiled cache was not preserved")
        print("PASS: corrupt compiled cache rebuilt; staging reclaimed; previous cache preserved")
        let receipt = model.appendingPathComponent("native-compiled.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as! [String: Any]
        object["os"] = "old OS"
        try JSONSerialization.data(withJSONObject: object).write(to: receipt)
        try require(!ModelStore.compiledValid(model), "Stale OS receipt accepted")
        _ = try ModelStore.prepare(cache: cache, statusFile: status)
        try require(ModelStore.compiledValid(model), "Stale compiled cache recovery failed")
        print("PASS: OS change recompiles the model without downloading model data")
    }
}
