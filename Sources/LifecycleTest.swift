import Foundation
import Darwin

func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    guard condition() else { throw PhononError(message: "FAIL: " + label) }
    print("PASS: " + label)
}

func waitForServer(_ server: PhononServer) async throws {
    let deadline = Date().addingTimeInterval(600)
    while server.status != .ready {
        if case .failed(let error) = server.status { throw PhononError(message: error) }
        guard Date() < deadline else { throw PhononError(message: "Readiness timeout") }
        try await Task.sleep(for: .milliseconds(250))
    }
}

func waitForExit(_ pid: Int32) async throws {
    let deadline = Date().addingTimeInterval(10)
    while kill(pid, 0) == 0 {
        guard Date() < deadline else { throw PhononError(message: "Owned server did not exit") }
        try await Task.sleep(for: .milliseconds(100))
    }
}

@main struct LifecycleTest {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let native = ProcessInfo.processInfo.environment["PHONON_TEST_NATIVE_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift")
        let data = ProcessInfo.processInfo.environment["PHONON_TEST_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("phonon-lifecycle-" + UUID().uuidString)
        let server = PhononServer(executable: native, dataDirectory: data)
        defer { server.stop(); if ProcessInfo.processInfo.environment["PHONON_TEST_DATA_DIR"] == nil { try? FileManager.default.removeItem(at: data) } }
        server.start()
        try await waitForServer(server)
        let firstPID = server.processIdentifier!
        if CommandLine.arguments.contains("--owner") {
            print("OWNER_CHILD_PID=\(firstPID)")
            fflush(stdout)
            try await Task.sleep(for: .seconds(300))
            return
        }
        try check(server.status == .ready, "automatic startup and model readiness")
        server.start()
        try check(server.processIdentifier == firstPID, "duplicate start keeps one process")
        let connection = try server.activeConnection()
        var unauthorized = URLRequest(url: connection.transcriptionURL)
        unauthorized.httpMethod = "POST"
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: unauthorized)
        try check((response as? HTTPURLResponse)?.statusCode == 401, "transcription requires the private token")
        kill(firstPID, SIGKILL)
        let deadline = Date().addingTimeInterval(600)
        while server.processIdentifier == firstPID || server.status != .ready {
            guard Date() < deadline else { throw PhononError(message: "Crash recovery timeout") }
            try await Task.sleep(for: .milliseconds(250))
        }
        try check(server.processIdentifier != firstPID, "automatic recovery after server crash")
        // Exhaust the bounded recovery budget rather than restart forever.
        for _ in 2...3 {
            let pid = server.processIdentifier!
            kill(pid, SIGKILL)
            let recoveryDeadline = Date().addingTimeInterval(600)
            while server.processIdentifier == pid || server.status != .ready {
                guard Date() < recoveryDeadline else { throw PhononError(message: "Recovery budget test timeout") }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        kill(server.processIdentifier!, SIGKILL)
        let failureDeadline = Date().addingTimeInterval(10)
        while server.processIdentifier != nil {
            guard Date() < failureDeadline else { throw PhononError(message: "Recovery did not stop") }
            try await Task.sleep(for: .milliseconds(100))
        }
        if case .failed(let message) = server.status {
            try check(message.contains("repeatedly stopped"), "repeated crashes stop with an actionable error")
        } else { throw PhononError(message: "Recovery budget did not produce an error") }
        server.stop()
        server.start()
        try await waitForServer(server)
        let secondPID = server.processIdentifier!
        server.stop()
        try await waitForExit(secondPID)
        try check(server.status == .stopped, "stop releases the owned process")
        server.start()
        server.stop()
        try await Task.sleep(for: .seconds(1))
        try check(server.processIdentifier == nil && server.status == .stopped, "stop cancels pending startup")
        server.start()
        server.stop()
        server.start()
        try await waitForServer(server)
        let resumedPID = server.processIdentifier!
        server.stop()
        try await waitForExit(resumedPID)
        try check(server.status == .stopped, "rapid stop/start does not let old tasks stop the new server")
        let stallScript = data.appendingPathComponent("stall.py")
        try "import time; time.sleep(60)".write(to: stallScript, atomically: true, encoding: .utf8)
        let python = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHONON_TEST_PYTHON"] ?? "/usr/bin/python3")
        let stalled = PhononServer(executable: python, dataDirectory: data,
                                   arguments: ["-I", "-B", "-u", stallScript.path], startupTimeout: 0.1)
        stalled.start()
        defer { stalled.stop() }
        try await Task.sleep(for: .seconds(1))
        if case .failed(let message) = stalled.status {
            try check(message.contains("timed out") && stalled.processIdentifier == nil, "startup timeout stops the helper")
        } else { throw PhononError(message: "Stalled startup did not fail") }
        let missing = PhononServer(executable: data.appendingPathComponent("missing"), dataDirectory: data)
        missing.start()
        defer { missing.stop() }
        try await Task.sleep(for: .milliseconds(500))
        if case .failed(let message) = missing.status {
            try check(message.contains("engine is missing"), "missing engine produces an actionable error")
        } else { throw PhononError(message: "Missing engine did not fail") }
    }
}
