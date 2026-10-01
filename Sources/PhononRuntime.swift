import Foundation
import CryptoKit
import Darwin

struct PhononRuntimeManifest: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let kind: String
        let url: URL
        let sha256: String
        let bytes: Int64
    }
    let version: String
    let assets: [Asset]
}

/// A small plugin can provision its pinned runtime from official distributions.
/// An OS file lock serializes installations, including across host processes.
struct PhononRuntime: Sendable {
    let manifestURL: URL
    let dataDirectory: URL

    func prepare(progress: @Sendable (String) -> Void) async throws -> URL {
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PhononRuntimeManifest.self, from: manifestData)
        guard !manifest.version.isEmpty,
              manifest.version.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) }) else {
            throw PhononError(message: "The Phonon runtime version is invalid.")
        }
        let digest = SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined()
        let runtimes = dataDirectory.appendingPathComponent("Runtime")
        let destination = runtimes.appendingPathComponent(manifest.version, isDirectory: true)
        let marker = destination.appendingPathComponent(".complete")
        let python = destination.appendingPathComponent("bin/python3.12")
        let fm = FileManager.default
        try fm.createDirectory(at: runtimes, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let lockFile = runtimes.appendingPathComponent("install.lock")
        let fd = open(lockFile.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw PhononError(message: "Cannot lock the Phonon runtime folder.") }
        defer { flock(fd, LOCK_UN); close(fd) }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw PhononError(message: "Cannot lock the Phonon runtime folder.") }
            progress("Waiting for Phonon setup…")
            try await Task.sleep(for: .milliseconds(250))
        }
        try Task.checkCancellation()
        if (try? String(contentsOf: marker, encoding: .utf8)) == digest,
           fm.isExecutableFile(atPath: python.path) { return destination }

        let stage = runtimes.appendingPathComponent(".install-" + UUID().uuidString)
        let downloads = stage.appendingPathComponent("downloads")
        let runtime = stage.appendingPathComponent("runtime")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for (index, asset) in manifest.assets.enumerated() {
            try Task.checkCancellation()
            guard asset.url.scheme == "https",
                  ["releases.astral.sh", "files.pythonhosted.org"].contains(asset.url.host),
                  ["python", "wheel"].contains(asset.kind) else {
                throw PhononError(message: "The Phonon runtime download manifest is invalid.")
            }
            progress("Setting up Phonon: \(asset.name) (\(index + 1)/\(manifest.assets.count))")
            var request = URLRequest(url: asset.url)
            request.setValue("TypeWhisper-Phonon/0.3", forHTTPHeaderField: "User-Agent")
            let (download, response) = try await session.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw PhononError(message: "Could not download \(asset.name). Check your internet connection and restart Phonon.")
            }
            let archive = downloads.appendingPathComponent("asset-\(index)")
            try fm.moveItem(at: download, to: archive)
            try verify(archive, asset: asset)
            if asset.kind == "python" {
                try await run("/usr/bin/tar", ["-xzf", archive.path, "--strip-components", "1", "-C", runtime.path])
            } else {
                let packages = runtime.appendingPathComponent("lib/python3.12/site-packages")
                try fm.createDirectory(at: packages, withIntermediateDirectories: true)
                try await run("/usr/bin/ditto", ["-x", "-k", archive.path, packages.path])
                // Wheels can place modules in a .data/{purelib,platlib} directory.
                for item in try fm.contentsOfDirectory(at: packages, includingPropertiesForKeys: nil) where item.pathExtension == "data" {
                    for library in ["purelib", "platlib"] {
                        let source = item.appendingPathComponent(library)
                        if fm.fileExists(atPath: source.path) {
                            try await run("/usr/bin/ditto", [source.path, packages.path])
                        }
                    }
                    try fm.removeItem(at: item)
                }
            }
            try fm.removeItem(at: archive)
        }
        progress("Checking the Phonon runtime…")
        try await run(runtime.appendingPathComponent("bin/python3.12").path,
                      ["-I", "-B", "-c", "import truststore, fermion, mlx.core, mlx_audio, mlx_lm, soundfile, scipy, zstandard; import importlib.util; assert importlib.util.find_spec('torch') is None"])
        try Task.checkCancellation()
        try digest.write(to: runtime.appendingPathComponent(".complete"), atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: destination.path) {
            // Preserve an incomplete or obsolete runtime rather than overwrite it.
            try fm.moveItem(at: destination, to: runtimes.appendingPathComponent(".previous-" + UUID().uuidString))
        }
        try fm.moveItem(at: runtime, to: destination)
        return destination
    }

    private func verify(_ file: URL, asset: PhononRuntimeManifest.Asset) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            size += Int64(data.count)
            hash.update(data: data)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard size == asset.bytes, actual == asset.sha256 else {
            throw PhononError(message: "Checksum verification failed for \(asset.name). Restart Phonon to retry setup.")
        }
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        try Task.checkCancellation()
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw PhononError(message: "Phonon runtime setup failed (\(URL(fileURLWithPath: executable).lastPathComponent), exit \(process.terminationStatus)). Check the available disk space and restart Phonon.")
            }
        }.value
        try Task.checkCancellation()
    }
}
