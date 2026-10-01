import Foundation
import Darwin
import MLX
import MLXAudioSTT
import MLXAudioCore

// Serial inference in an owned native helper. No model crosses a concurrency
// boundary. Only parent/pipe monitoring runs on background threads.
enum NativeServer {
    static func run() throws {
        guard let line = readLine(), let data = line.data(using: .utf8),
              let config = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = config["token"], let ready = config["ready_file"], let instance = config["instance"],
              let cache = ProcessInfo.processInfo.environment["FERMION_CACHE_DIR"] else {
            throw PrototypeError.invalid("Missing native engine configuration")
        }
        let dataDirectory = URL(fileURLWithPath: ready).deletingLastPathComponent()
        // Reclaim an interrupted load only after its owning process has exited.
        for previous in try FileManager.default.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)
        where previous.lastPathComponent.hasPrefix("native-load-") {
            let pieces = previous.lastPathComponent.split(separator: "-")
            if pieces.count >= 4, let pid = Int32(pieces[2]), pid > 0,
               Darwin.kill(pid, 0) != 0, errno == ESRCH {
                try? FileManager.default.removeItem(at: previous)
            }
        }
        let parent = getppid()
        DispatchQueue.global().async {
            var bytes = [UInt8](repeating: 0, count: 1024)
            while Darwin.read(STDIN_FILENO, &bytes, bytes.count) > 0 {}
            Darwin._exit(0)
        }
        DispatchQueue.global().async {
            while getppid() == parent { Thread.sleep(forTimeInterval: 1) }
            Darwin._exit(0)
        }
        let directory = URL(fileURLWithPath: cache).appendingPathComponent("speech/FermionResearch__Phonon-2/model_phonon2_c4c_int6")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.fermion").path) else {
            throw PrototypeError.invalid("The Swift test build needs the existing Phonon-2 model in PluginData/Models. Download it with Phonon Local 0.3.1 first, then install this test build.")
        }
        print("[phonon-swift] Loading Phonon-2 with native MLX…")
        fflush(stdout)
        let scratch = dataDirectory.appendingPathComponent("native-load-\(getpid())-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        var weights: [String: MLXArray]? = try PhononContainer.read(directory.appendingPathComponent("model.fermion"))
        try MLX.save(arrays: weights!, url: scratch.appendingPathComponent("model.safetensors"))
        weights = nil
        Memory.clearCache()
        try FileManager.default.copyItem(at: directory.appendingPathComponent("config.json"), to: scratch.appendingPathComponent("config.json"))
        let model = try ParakeetModel.fromDirectory(scratch, computeDType: .bfloat16)
        try FileManager.default.removeItem(at: scratch)
        // Warm GPU kernels before publishing readiness. User audio stays in memory.
        _ = model.generate(audio: MLXArray.zeros([16000]))
        Stream.defaultStream.synchronize()
        Memory.clearCache()
        signal(SIGPIPE, SIG_IGN)
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw PrototypeError.invalid("Cannot create native engine socket") }
        defer { Darwin.close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 8) == 0 else { throw PrototypeError.invalid("Cannot bind native engine to loopback") }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let located = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) }
        }
        guard located == 0 else { throw PrototypeError.invalid("Cannot locate native engine port") }
        let port = Int(UInt16(bigEndian: address.sin_port))
        let metadata: [String: Any] = ["port": port, "pid": getpid(), "instance": instance]
        try JSONSerialization.data(withJSONObject: metadata).write(to: URL(fileURLWithPath: ready), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ready)
        print("[phonon-swift] Ready: native Swift/MLX, loopback port \(port), no Python")
        fflush(stdout)
        while true {
            let connection = accept(listener, nil, nil)
            if connection < 0 { if errno == EINTR { continue }; throw PrototypeError.invalid("Native engine accept failed") }
            var timeout = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            do { try handle(connection, token: token, model: model) }
            catch { respond(connection, status: 400, object: ["error": String(describing: error)]) }
            Darwin.close(connection)
        }
    }

    private static func handle(_ socket: Int32, token: String, model: ParakeetModel) throws {
        var request = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        var split: Range<Data.Index>?
        while split == nil {
            let count = Darwin.read(socket, &buffer, buffer.count)
            guard count > 0 else { throw PrototypeError.invalid("Incomplete request") }
            request.append(contentsOf: buffer.prefix(count))
            split = request.range(of: Data("\r\n\r\n".utf8))
            guard (split?.lowerBound ?? request.count) <= 16384 else { throw PrototypeError.invalid("Request headers too large") }
        }
        let separator = split!
        let lines = String(decoding: request[..<separator.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw PrototypeError.invalid("Duplicate request header") }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if lines[0].hasPrefix("GET /health ") {
            respond(socket, status: 200, object: ["status": "ok", "kind": "speech", "model": "FermionResearch/Phonon-2", "engine": "swift-mlx"])
            return
        }
        guard lines[0].hasPrefix("POST /v1/audio/transcriptions ") else { respond(socket, status: 404, object: ["error": "Unknown endpoint"]); return }
        guard headers["authorization"] == "Bearer " + token else { respond(socket, status: 401, object: ["error": "Unauthorised"]); return }
        guard headers["transfer-encoding"] == nil,
              let lengthString = headers["content-length"], let length = Int(lengthString), (44...31_100_000).contains(length),
              let contentType = headers["content-type"], contentType.hasPrefix("multipart/form-data;"),
              let boundaryPart = contentType.components(separatedBy: "boundary=").last, !boundaryPart.isEmpty, boundaryPart.count <= 128 else {
            throw PrototypeError.invalid("Expected a bounded multipart WAV request")
        }
        let total = separator.upperBound + length
        while request.count < total {
            let count = Darwin.read(socket, &buffer, min(buffer.count, total - request.count))
            guard count > 0 else { throw PrototypeError.invalid("Incomplete audio upload") }
            request.append(contentsOf: buffer.prefix(count))
        }
        let body = Data(request[separator.upperBound..<total])
        let boundary = boundaryPart.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard let filename = body.range(of: Data("filename=\"audio.wav\"".utf8)),
              let start = body.range(of: Data("\r\n\r\n".utf8), options: [], in: filename.upperBound..<body.endIndex),
              let end = body.range(of: Data(("\r\n--" + boundary).utf8), options: [], in: start.upperBound..<body.endIndex) else {
            throw PrototypeError.invalid("Missing audio file")
        }
        let samples = try decodeWAV(Data(body[start.upperBound..<end.lowerBound]))
        let started = Date()
        let result = model.generate(audio: MLXArray(samples))
        Stream.defaultStream.synchronize()
        respond(socket, status: 200, object: ["text": result.text])
        print("[phonon-swift] Transcribed \(Double(samples.count) / 16000) seconds in \(Date().timeIntervalSince(started)) seconds")
        fflush(stdout)
        Memory.clearCache()
    }

    static func decodeWAV(_ bytes: Data) throws -> [Float] {
        guard bytes.count >= 44, bytes.prefix(4) == Data("RIFF".utf8), bytes[8..<12] == Data("WAVE".utf8) else { throw PrototypeError.invalid("Invalid WAV") }
        func u16(_ offset: Int) -> UInt16 { bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian } }
        func u32(_ offset: Int) -> UInt32 { bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian } }
        var position = 12, format = 0, channels = 0, rate = 0, bits = 0
        var payload: Range<Int>?
        while position + 8 <= bytes.count {
            let length = Int(u32(position + 4)), start = position + 8
            guard length <= bytes.count - start else { throw PrototypeError.invalid("Truncated WAV chunk") }
            let name = String(decoding: bytes[position..<position + 4], as: UTF8.self)
            if name == "fmt " {
                guard length >= 16 else { throw PrototypeError.invalid("Invalid WAV format") }
                format = Int(u16(start)); channels = Int(u16(start + 2)); rate = Int(u32(start + 4)); bits = Int(u16(start + 14))
            } else if name == "data" { payload = start..<start + length }
            position = start + length + length % 2
        }
        guard let payload, (1...8).contains(channels), (8000...192000).contains(rate),
              (format == 1 && bits == 16) || (format == 3 && bits == 32) else { throw PrototypeError.invalid("Expected PCM16 or float32 WAV") }
        let frameBytes = channels * bits / 8
        guard payload.count % frameBytes == 0, payload.count > 0 else { throw PrototypeError.invalid("Invalid WAV frame size") }
        var samples = [Float](repeating: 0, count: payload.count / frameBytes)
        bytes.withUnsafeBytes { raw in
            for frame in samples.indices {
                for channel in 0..<channels {
                    let offset = payload.lowerBound + frame * frameBytes + channel * bits / 8
                    if bits == 16 { samples[frame] += Float(Int16(bitPattern: u16(offset))) / 32768 / Float(channels) }
                    else { samples[frame] += Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian) / Float(channels) }
                }
            }
        }
        guard samples.allSatisfy(\.isFinite) else { throw PrototypeError.invalid("Non-finite audio samples") }
        return rate == 16000 ? samples : try resampleAudio(samples, from: rate, to: 16000)
    }

    private static func respond(_ socket: Int32, status: Int, object: [String: String]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        var response = Data("HTTP/1.1 \(status) Response\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        response.withUnsafeBytes { raw in
            var position = 0
            while position < raw.count {
                let count = Darwin.write(socket, raw.baseAddress!.advanced(by: position), raw.count - position)
                if count <= 0 { break }
                position += count
            }
        }
    }
}
