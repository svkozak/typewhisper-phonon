import Foundation
import Darwin

struct PhononConnection: Sendable {
    let port: Int
    let token: String
    var transcriptionURL: URL { URL(string: "http://127.0.0.1:\(port)/v1/audio/transcriptions")! }
}

enum PhononServerState: Sendable, Equatable {
    case stopped, starting, ready, installing(String), failed(String)
    var message: String {
        switch self {
        case .stopped: "Server stopped"
        case .installing(let message): message
        case .starting: "Starting Phonon… Loading the model may take a moment."
        case .ready: "Ready for English dictation"
        case .failed(let message): message
        }
    }
}

/// Mutable process/lifetime state is protected by lock. Each activation owns one
/// controller; stopping it prevents a pending task from launching another process.
final class PhononServer: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var generation = 0
    private var state: PhononServerState = .stopped
    private var process: Process?
    private var lifetime: Pipe?
    private var connection: PhononConnection?
    private var supervisor: Task<Void, Never>?
    private let runtime: URL
    private let setup: PhononRuntime?
    private let nativeExecutable: URL?
    private let helper: URL
    private let dataDirectory: URL
    private let changed: @Sendable () -> Void
    private let startupTimeout: TimeInterval

    init(runtime: URL, helper: URL, dataDirectory: URL, startupTimeout: TimeInterval = 600, setup: PhononRuntime? = nil, nativeExecutable: URL? = nil,
         changed: @escaping @Sendable () -> Void = {}) {
        self.runtime = runtime
        self.setup = setup
        self.nativeExecutable = nativeExecutable
        self.helper = helper
        self.dataDirectory = dataDirectory
        self.startupTimeout = startupTimeout
        self.changed = changed
    }

    var status: PhononServerState {
        lock.withLock {
            if state == .ready, process?.isRunning != true { return .starting }
            return state
        }
    }

    var processIdentifier: Int32? { lock.withLock { process?.processIdentifier } }

    func activeConnection() throws -> PhononConnection {
        try lock.withLock {
            guard enabled, state == .ready, process?.isRunning == true, let connection else {
                throw PhononError(message: state == .ready ? "Phonon is restarting. Retry shortly." : state.message)
            }
            return connection
        }
    }

    func start() {
        lock.withLock {
            guard !enabled else { return }
            enabled = true
            generation += 1
            let runGeneration = generation
            state = .starting
            supervisor = Task { [weak self] in await self?.supervise(generation: runGeneration) }
        }
        notify()
    }

    func stop() {
        lock.withLock {
            enabled = false
            generation += 1
            supervisor?.cancel()
            supervisor = nil
            stopProcessLocked()
            state = .stopped
        }
        changed()
    }

    deinit { stop() }

    private func stopProcessLocked() {
        connection = nil
        try? lifetime?.fileHandleForWriting.close()
        lifetime = nil
        if let process, process.isRunning { process.terminate() }
        // Parent pipe EOF also stops the child if termination is delayed.
        process = nil
    }

    private func notify() {
        guard lock.withLock({ enabled }) else { return }
        changed()
    }

    private struct Launch: Sendable {
        let process: Process
        let readyFile: URL
        let instance: String
        let token: String
    }

    private func launch(runtime: URL, generation expectedGeneration: Int) throws -> Launch {
        try lock.withLock {
            guard enabled, generation == expectedGeneration, !Task.isCancelled else { throw CancellationError() }
            stopProcessLocked()
            state = .starting
            let standalonePython = runtime.appendingPathComponent("bin/python3.12")
            let isBundledRuntime = FileManager.default.isExecutableFile(atPath: standalonePython.path)
            let python = nativeExecutable ?? (isBundledRuntime ? standalonePython : runtime.appendingPathComponent(".venv/bin/python"))
            guard FileManager.default.isExecutableFile(atPath: python.path),
                  FileManager.default.fileExists(atPath: helper.path) else {
                throw PhononError(message: "Phonon runtime is missing. Run scripts/setup-runtime.sh in \(runtime.path), then restart Phonon.")
            }
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            // Bound logs to the latest launch. Audio and credentials are not logged here.
            let logURL = dataDirectory.appendingPathComponent("server.log")
            FileManager.default.createFile(atPath: logURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            let log = try FileHandle(forWritingTo: logURL)
            defer { try? log.close() }
            let instance = UUID().uuidString
            let readyFile = dataDirectory.appendingPathComponent("server-\(instance).json")
            let token = UUID().uuidString + UUID().uuidString
            let input = Pipe()
            let child = Process()
            child.executableURL = python
            child.arguments = nativeExecutable == nil ? ["-I", "-B", "-u", helper.path] : ["--serve"]
            child.currentDirectoryURL = runtime
            var environment = ProcessInfo.processInfo.environment
            environment["HF_HOME"] = dataDirectory.appendingPathComponent("Models/huggingface").path
            environment["FERMION_CACHE_DIR"] = dataDirectory.appendingPathComponent("Models/fermion").path
            environment["PYTHONUNBUFFERED"] = "1"
            child.environment = environment
            child.standardInput = input
            child.standardOutput = log
            child.standardError = log
            try child.run()
            process = child
            lifetime = input
            // The child reads config, then watches this pipe until its owner closes it.
            let config: [String: String] = ["ready_file": readyFile.path, "instance": instance, "token": token]
            do {
                var data = try JSONSerialization.data(withJSONObject: config)
                data.append(10)
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForReading.close()
            } catch {
                stopProcessLocked()
                throw error
            }
            return Launch(process: child, readyFile: readyFile, instance: instance, token: token)
        }
    }

    private func waitUntilReady(_ launch: Launch) async throws -> PhononConnection {
        struct Ready: Decodable { let port: Int; let pid: Int32; let instance: String }
        struct Health: Decodable { let status: String; let kind: String; let model: String }
        struct Progress: Decodable { let message: String; let failed: Bool }
        let statusFile = URL(fileURLWithPath: launch.readyFile.path + ".status")
        let deadline = Date().addingTimeInterval(startupTimeout)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            try? FileManager.default.removeItem(at: launch.readyFile)
            try? FileManager.default.removeItem(at: statusFile)
        }
        while Date() < deadline {
            try Task.checkCancellation()
            if nativeExecutable != nil,
               let data = try? Data(contentsOf: statusFile),
               let progress = try? JSONDecoder().decode(Progress.self, from: data) {
                if progress.failed { throw PhononError(message: progress.message) }
                let updated = lock.withLock {
                    guard enabled, process === launch.process, state != .installing(progress.message) else { return false }
                    state = .installing(progress.message)
                    return true
                }
                if updated { notify() }
            }
            guard launch.process.isRunning else {
                throw PhononError(message: "Phonon server exited during startup. Check server.log in the plugin data folder.")
            }
            if let data = try? Data(contentsOf: launch.readyFile),
               let ready = try? JSONDecoder().decode(Ready.self, from: data),
               ready.pid == launch.process.processIdentifier, ready.instance == launch.instance,
               (1...65535).contains(ready.port) {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:\(ready.port)/health")!)
                request.timeoutInterval = 2
                if let (data, response) = try? await session.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let health = try? JSONDecoder().decode(Health.self, from: data),
                   health.status == "ok", health.kind == "speech", health.model == "FermionResearch/Phonon-2" {
                    return PhononConnection(port: ready.port, token: launch.token)
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PhononError(message: "Phonon startup timed out. Check the runtime, model download, and server.log, then restart Phonon.")
    }

    private func supervise(generation expectedGeneration: Int) async {
        var crashCount = 0
        while !Task.isCancelled {
            do {
                let preparedRuntime: URL
                if let setup {
                    preparedRuntime = try await setup.prepare { [weak self] message in
                        guard let self else { return }
                        let active = self.lock.withLock {
                            guard self.enabled, self.generation == expectedGeneration else { return false }
                            self.state = .installing(message)
                            return true
                        }
                        if active { self.notify() }
                    }
                } else { preparedRuntime = runtime }
                let launch = try launch(runtime: preparedRuntime, generation: expectedGeneration)
                notify()
                let readyConnection = try await waitUntilReady(launch)
                let accepted = lock.withLock {
                    guard enabled, generation == expectedGeneration, process === launch.process, !Task.isCancelled else { return false }
                    connection = readyConnection
                    state = .ready
                    return true
                }
                guard accepted else { return }
                notify()
                while launch.process.isRunning {
                    try await Task.sleep(for: .seconds(1))
                }
                crashCount += 1
                guard crashCount <= 3 else {
                    throw PhononError(message: "Phonon repeatedly stopped. Check server.log, then restart Phonon.")
                }
                let recovering = lock.withLock {
                    guard enabled, generation == expectedGeneration else { return false }
                    connection = nil; state = .starting
                    return true
                }
                guard recovering else { return }
                notify()
                try await Task.sleep(for: .seconds(crashCount))
            } catch is CancellationError {
                return
            } catch {
                let reported = lock.withLock {
                    guard enabled, generation == expectedGeneration else { return false }
                    stopProcessLocked()
                    state = .failed(error.localizedDescription)
                    return true
                }
                if reported { notify() }
                return
            }
        }
    }
}
