import Foundation
import CryptoKit
import CoreML
import Darwin

/// Downloads data only. All executable code remains in the signed bundle.
enum ModelStore {
    static let revision = "e931079df1f6bff26f5f416c1c8880e76a0cf2a3"
    static let source = "https://huggingface.co/FermionResearch/Phonon-2-CoreML"
    static let packageName = "Phonon-2.mlpackage"
    static let compiledName = "Phonon-2.mlmodelc"
    struct Artifact: Sendable {
        let path: String
        let bytes: Int64
        let sha256: String
    }
    // Pin every input, including package metadata and attribution, before Core ML
    // or the upstream decoder sees it. Never trust a remotely supplied checksum.
    static let artifacts: [Artifact] = [
        Artifact(path: "manifest.json", bytes: 1428, sha256: "ab3fb5dfd3fc07b1d8a24379d04418f458d0443ba6359d3a5ab2f098a7d64089"),
        Artifact(path: "Phonon-2.mlpackage/Manifest.json", bytes: 617, sha256: "6ebc9309aea0e16bda9c7558521fef6307fac0afba9a5b4959fea45ed7cd0429"),
        Artifact(path: "Phonon-2.mlpackage/Data/com.apple.CoreML/model.mlmodel", bytes: 2500482, sha256: "4f6790ec94fe4429b10397c013563d0a51119953ff6d3da466bbcb23a25dee2a"),
        Artifact(path: "Phonon-2.mlpackage/Data/com.apple.CoreML/weights/weight.bin", bytes: 329186560, sha256: "93aa991318a00ed492fdbb724e7bca4e6a69c6cf671ab4f14a14ef6101e7648b"),
        Artifact(path: "decoder.bin", bytes: 13301279, sha256: "36fa7202dda85c603af60d930ab88d7e9f0d2a619490aff46f5384db924cfa70"),
        Artifact(path: "NOTICE", bytes: 3084, sha256: "b468a23a1ce2c5181ea4050432bb68713a6468ce2e452927228d24f3d56226be"),
        Artifact(path: "LICENSE-CODE-Apache-2.0.txt", bytes: 11358, sha256: "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"),
        Artifact(path: "LICENSE-WEIGHTS-CC-BY-4.0.txt", bytes: 18657, sha256: "9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411"),
    ]
    static var downloadBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    static func parent(cache: URL) -> URL { cache.appendingPathComponent("speech/FermionResearch__Phonon-2-CoreML") }
    static func directory(cache: URL) -> URL { parent(cache: cache).appendingPathComponent(revision) }

    static func status(_ message: String, file: URL, error: Bool = false) {
        let object: [String: Any] = ["message": message, "failed": error]
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    static func hash(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Reject links in every path component and reject wrong sizes before hashing.
    static func regularFile(_ file: URL, under root: URL, bytes: Int64) -> Bool {
        var rootInfo = stat()
        guard file.path.hasPrefix(root.path + "/"), lstat(root.path, &rootInfo) == 0,
              rootInfo.st_mode & S_IFMT == S_IFDIR else { return false }
        let relative = String(file.path.dropFirst(root.path.count + 1))
        var current = root
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            var info = stat()
            guard lstat(current.path, &info) == 0 else { return false }
            if current == file {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_size == bytes else { return false }
            } else if info.st_mode & S_IFMT != S_IFDIR { return false }
        }
        return current == file
    }

    static func valid(_ directory: URL) -> Bool {
        artifacts.allSatisfy { artifact in
            let file = directory.appendingPathComponent(artifact.path)
            return regularFile(file, under: directory, bytes: artifact.bytes) && (try? hash(file)) == artifact.sha256
        }
    }

    private static func withLock<T>(cache: URL, statusFile: URL, body: (URL) throws -> T) throws -> T {
        let parent = parent(cache: cache)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(parent.appendingPathComponent(".native-model.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw PrototypeError.invalid("Cannot lock the model folder") }
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        status("Checking Phonon-2 model…", file: statusFile)
        guard flock(descriptor, LOCK_EX) == 0 else { throw PrototypeError.invalid("Cannot lock the model folder") }
        return try body(parent)
    }

    static func ensure(cache: URL, statusFile: URL) throws -> URL {
        try withLock(cache: cache, statusFile: statusFile) { try install(parent: $0, statusFile: statusFile) }
    }

    /// Keep the compiled model at a stable path in PluginData. This bypasses the
    /// library's shared ~/Library/Caches location and permits verified recovery.
    static func prepare(cache: URL, statusFile: URL) throws -> URL {
        try withLock(cache: cache, statusFile: statusFile) { parent in
            let model = try install(parent: parent, statusFile: statusFile)
            try prepareCompiled(model, statusFile: statusFile)
            return model
        }
    }

    private static func install(parent: URL, statusFile: URL) throws -> URL {
        let fm = FileManager.default
        let directory = parent.appendingPathComponent(revision)
        // The lock proves that no live installer owns these staging folders.
        for old in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        where old.lastPathComponent.hasPrefix(".native-download-") { try fm.removeItem(at: old) }
        if valid(directory) { return directory }
        let stage = parent.appendingPathComponent(".native-download-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        var downloaded: Int64 = 0
        for artifact in artifacts {
            let destination = stage.appendingPathComponent(artifact.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try download(artifact, to: destination, downloaded: downloaded, statusFile: statusFile)
            guard regularFile(destination, under: stage, bytes: artifact.bytes), try hash(destination) == artifact.sha256 else {
                throw PrototypeError.invalid("Phonon-2 download failed its integrity check. Select Retry to download again.")
            }
            downloaded += artifact.bytes
        }
        status("Verifying Phonon-2 download…", file: statusFile)
        guard valid(stage) else { throw PrototypeError.invalid("Phonon-2 model failed its integrity check") }
        let receipt = ["revision": revision, "license": "CC-BY-4.0", "source": source]
        try JSONEncoder().encode(receipt).write(to: stage.appendingPathComponent("native-download.json"))
        // Preserve a damaged prior cache and all old MLX caches for rollback.
        try publish(stage, to: directory, backupPrefix: "model-backup-")
        return directory
    }

    static func download(_ artifact: Artifact, to destination: URL, downloaded: Int64, statusFile: URL) throws {
        status("Downloading Phonon-2: \(downloaded * 100 / downloadBytes)% (345 MB)", file: statusFile)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 540
        let delegate = ModelDownload(artifact: artifact, destination: destination, downloaded: downloaded, statusFile: statusFile)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "\(source)/resolve/\(revision)/\(artifact.path)")!
        session.downloadTask(with: url).resume()
        delegate.completed.wait()
        if let error = delegate.resultError {
            throw PrototypeError.invalid("Phonon-2 download failed: \(error.localizedDescription). Check the internet connection and select Retry.")
        }
    }

    private struct CompiledFile: Codable, Equatable {
        let bytes: Int64
        let sha256: String
    }
    private struct CompiledReceipt: Codable {
        let revision: String
        let os: String
        let files: [String: CompiledFile]
    }
    private static var os: String { ProcessInfo.processInfo.operatingSystemVersionString }
    private static func inventory(_ directory: URL) throws -> [String: CompiledFile] {
        let fm = FileManager.default
        var root = stat()
        guard lstat(directory.path, &root) == 0, root.st_mode & S_IFMT == S_IFDIR else {
            throw PrototypeError.invalid("Invalid compiled model folder")
        }
        var files: [String: CompiledFile] = [:]
        var total: Int64 = 0
        var entries = 0
        // Track relative names explicitly. Foundation enumeration can change
        // /var to /private/var even after resolvingSymlinksInPath().
        var pending: [(URL, String)] = [(directory, "")]
        while let (folder, prefix) = pending.popLast() {
            for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                entries += 1
                var info = stat()
                guard entries <= 4096, lstat(file.path, &info) == 0 else { throw PrototypeError.invalid("Invalid compiled model entry") }
                let path = prefix + file.lastPathComponent
                if info.st_mode & S_IFMT == S_IFDIR { pending.append((file, path + "/")); continue }
                guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw PrototypeError.invalid("Invalid compiled model file") }
                total += info.st_size
                guard total <= 8_000_000_000 else { throw PrototypeError.invalid("Compiled model is too large") }
                files[path] = CompiledFile(bytes: info.st_size, sha256: try hash(file))
            }
        }
        guard !files.isEmpty else { throw PrototypeError.invalid("Compiled model is empty") }
        return files
    }
    static func compiledValid(_ directory: URL) -> Bool {
        let receiptURL = directory.appendingPathComponent("native-compiled.json")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: receiptURL.path)[.size] as? NSNumber)?.int64Value,
              (1...1_000_000).contains(size), regularFile(receiptURL, under: directory, bytes: size),
              let data = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(CompiledReceipt.self, from: data),
              receipt.revision == revision, receipt.os == os,
              let files = try? inventory(directory.appendingPathComponent(compiledName)) else { return false }
        return files == receipt.files
    }
    private static func prepareCompiled(_ directory: URL, statusFile: URL) throws {
        let fm = FileManager.default
        for old in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where old.lastPathComponent.hasPrefix(".native-compile-") { try fm.removeItem(at: old) }
        if compiledValid(directory) { return }
        status("Preparing Phonon-2 (first setup can take several minutes)…", file: statusFile)
        let temporary = try MLModel.compileModel(at: directory.appendingPathComponent(packageName))
        defer { try? fm.removeItem(at: temporary) }
        let stage = directory.appendingPathComponent(".native-compile-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        try fm.moveItem(at: temporary, to: stage)
        let files = try inventory(stage)
        try publish(stage, to: directory.appendingPathComponent(compiledName), backupPrefix: "compiled-backup-")
        let receipt = CompiledReceipt(revision: revision, os: os, files: files)
        try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent("native-compiled.json"), options: .atomic)
    }
    private static func publish(_ stage: URL, to destination: URL, backupPrefix: String) throws {
        let fm = FileManager.default
        let backup = destination.deletingLastPathComponent().appendingPathComponent(backupPrefix + UUID().uuidString)
        let hadPrevious = fm.fileExists(atPath: destination.path)
        if hadPrevious { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: stage, to: destination) }
        catch {
            if hadPrevious { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
    }
}

// URLSession delegates run on a serial delegate queue. The failure is protected
// because the main thread reads it after the completion semaphore.
private final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let artifact: ModelStore.Artifact
    let destination: URL
    let downloaded: Int64
    let statusFile: URL
    let completed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var failure: Error?
    private var lastPercent = -1
    var resultError: Error? { lock.withLock { failure } }
    init(artifact: ModelStore.Artifact, destination: URL, downloaded: Int64, statusFile: URL) {
        self.artifact = artifact; self.destination = destination; self.downloaded = downloaded; self.statusFile = statusFile
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > artifact.bytes { downloadTask.cancel(); return }
        let percent = Int((downloaded + totalBytesWritten) * 100 / ModelStore.downloadBytes)
        if percent != lastPercent { lastPercent = percent; ModelStore.status("Downloading Phonon-2: \(percent)% (345 MB)", file: statusFile) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200,
                  (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value == artifact.bytes else {
                throw PrototypeError.invalid("The model server returned an invalid response")
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { lock.withLock { failure = error } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { lock.withLock { failure = error } }
        completed.signal()
    }
}
