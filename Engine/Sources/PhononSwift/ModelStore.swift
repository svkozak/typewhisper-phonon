import Foundation
import CryptoKit
import Darwin
import CZstd

/// Downloads data only. All executable code remains in the signed bundle.
enum ModelStore {
    static let revision = "ca1bef26bcd8ef4a7e16d0636d8a77bb25e298ee"
    static let archiveHash = "98125795b6dda72f5c6eee9ba33d19815df65dcb18b50a357bf9f73c9935309e"
    static let containerHash = "4b6bfa3a12cc3c4e0a54f2ab3ec4ca7a842b09e5c7ecfc8e7ca0ac6cc8c11468"
    static let configHash = "d0daad3b2a182893844f4abdc11e4f5b7083f7d42c8ad7e8203f71559785a31b"
    static let archiveBytes: Int64 = 163_515_201

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

    static func valid(_ directory: URL) -> Bool {
        (try? hash(directory.appendingPathComponent("model.fermion"))) == containerHash &&
        (try? hash(directory.appendingPathComponent("config.json"))) == configHash
    }

    static func ensure(cache: URL, statusFile: URL) throws -> URL {
        let fm = FileManager.default
        let parent = cache.appendingPathComponent("speech/FermionResearch__Phonon-2")
        let directory = parent.appendingPathComponent("model_phonon2_c4c_int6")
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(parent.appendingPathComponent(".native-model.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw PrototypeError.invalid("Cannot lock the model folder") }
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        status("Checking Phonon-2 model…", file: statusFile)
        guard flock(descriptor, LOCK_EX) == 0 else { throw PrototypeError.invalid("Cannot lock the model folder") }
        if valid(directory) { return directory }
        // A process can exit during download. The lock proves no other installer
        // owns these staging folders. Never remove the user's installed model.
        for old in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        where old.lastPathComponent.hasPrefix(".native-download-") { try fm.removeItem(at: old) }
        let stage = parent.appendingPathComponent(".native-download-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        let archive = stage.appendingPathComponent("model.tar.zst")
        status("Downloading Phonon-2 (164 MB)…", file: statusFile)
        try download(to: archive, statusFile: statusFile)
        status("Verifying Phonon-2 download…", file: statusFile)
        guard (try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.int64Value == archiveBytes,
              try hash(archive) == archiveHash else { throw PrototypeError.invalid("Phonon-2 download failed its integrity check. Restart Phonon to retry.") }
        status("Unpacking Phonon-2…", file: statusFile)
        let tar = stage.appendingPathComponent("model.tar")
        guard phonon_decompress(archive.path, tar.path, 180_000_000) == 0 else { throw PrototypeError.invalid("Cannot unpack the Phonon-2 download") }
        let unpacked = stage.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try extract(tar, to: unpacked)
        guard valid(unpacked) else { throw PrototypeError.invalid("Phonon-2 model failed its integrity check") }
        let receipt: [String: String] = ["revision": revision, "archive_sha256": archiveHash, "container_sha256": containerHash, "license": "CC-BY-4.0", "source": "https://huggingface.co/FermionResearch/Phonon-2"]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: unpacked.appendingPathComponent("native-download.json"))
        // Preserve an incompatible or damaged previous cache for inspection.
        let backup = parent.appendingPathComponent("model-backup-" + UUID().uuidString)
        let hadPrevious = fm.fileExists(atPath: directory.path)
        if hadPrevious { try fm.moveItem(at: directory, to: backup) }
        do { try fm.moveItem(at: unpacked, to: directory) }
        catch {
            if hadPrevious { try? fm.moveItem(at: backup, to: directory) }
            throw error
        }
        return directory
    }

    static func download(to destination: URL, statusFile: URL) throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 540
        let delegate = ModelDownload(destination: destination, statusFile: statusFile)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://huggingface.co/FermionResearch/Phonon-2/resolve/\(revision)/phonon-2.bps.tar.zst")!
        session.downloadTask(with: url).resume()
        delegate.completed.wait()
        if let error = delegate.resultError { throw PrototypeError.invalid("Phonon-2 download failed: \(error.localizedDescription). Check the internet connection and restart Phonon to retry.") }
    }

    /// Accept only the four regular files in the pinned archive. No paths,
    /// links, extensions, duplicate entries, or unbounded allocations.
    static func extract(_ tar: URL, to directory: URL) throws {
        let expected = ["bps_manifest.json": 799, "config.json": 277493, "model.fermion": 177438361, "packed_manifest.json": 821]
        let input = try FileHandle(forReadingFrom: tar)
        defer { try? input.close() }
        var seen = Set<String>()
        func read(_ count: Int) throws -> Data {
            let data = try input.read(upToCount: count) ?? Data()
            guard data.count == count else { throw PrototypeError.invalid("Truncated model archive") }
            return data
        }
        func string(_ data: Data) -> String { String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces) }
        while true {
            let header = try read(512)
            if header.allSatisfy({ $0 == 0 }) {
                guard try read(512).allSatisfy({ $0 == 0 }), seen == Set(expected.keys) else { throw PrototypeError.invalid("Incomplete model archive") }
                return
            }
            let name = string(header[0..<100])
            let checksum = header.enumerated().reduce(0) { $0 + ((148..<156).contains($1.offset) ? 32 : Int($1.element)) }
            guard let size = Int(string(header[124..<136]), radix: 8), expected[name] == size,
                  (header[156] == 0 || header[156] == 48), header[345..<500].allSatisfy({ $0 == 0 }),
                  Int(string(header[148..<156]), radix: 8) == checksum, seen.insert(name).inserted else { throw PrototypeError.invalid("Unexpected entry in model archive") }
            let file = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: file)
            do {
                var remaining = size
                while remaining > 0 { let bytes = try read(min(1_048_576, remaining)); try output.write(contentsOf: bytes); remaining -= bytes.count }
                try output.close()
            } catch { try? output.close(); throw error }
            let padding = (512 - size % 512) % 512
            if padding > 0 { _ = try read(padding) }
        }
    }
}

// URLSession delegates run on its serial delegate queue. The error is protected
// because the helper's main thread reads it after the completion semaphore.
private final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let statusFile: URL
    let completed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var failure: Error?
    private var lastPercent = -1
    var resultError: Error? { lock.withLock { failure } }
    init(destination: URL, statusFile: URL) { self.destination = destination; self.statusFile = statusFile }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ModelStore.archiveBytes { downloadTask.cancel(); return }
        let percent = Int(totalBytesWritten * 100 / ModelStore.archiveBytes)
        if percent != lastPercent { lastPercent = percent; ModelStore.status("Downloading Phonon-2: \(percent)% (164 MB)", file: statusFile) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw PrototypeError.invalid("The model server returned an unsuccessful response") }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { lock.withLock { failure = error } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { lock.withLock { failure = error } }
        completed.signal()
    }
}
