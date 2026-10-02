import Foundation
import MLX

enum PrototypeError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

// Port of Fermion 0.2.7's fermion_container.py and hf_to_mlx_parakeet.py.
// Feasibility path: expand the SAME compressed weights to float16, without Python.
enum PhononContainer {
    struct Header: Decodable { let format: String; let index: [Record] }
    struct Record: Decodable { let n: String; let k: String; let shape: [Int]; let b: Int }

    static func read(_ url: URL) throws -> [String: MLXArray] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func readExactly(_ count: Int) throws -> Data {
            guard count >= 0, count <= 256 * 1024 * 1024,
                  let bytes = try handle.read(upToCount: count), bytes.count == count else {
                throw PrototypeError.invalid("Truncated or oversized container record")
            }
            return bytes
        }
        let length = try readExactly(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard length < 4 * 1024 * 1024 else { throw PrototypeError.invalid("Oversized container header") }
        let header = try JSONDecoder().decode(Header.self, from: readExactly(Int(length)))
        guard header.format == "fermion-five-value-parakeet-v1", header.index.count == 723 else {
            throw PrototypeError.invalid("This prototype expects Phonon-2's 723-record container")
        }
        var weights: [String: MLXArray] = [:]
        var fiveValueCount = 0
        for record in header.index {
            guard record.shape.count <= 4, record.shape.allSatisfy({ $0 > 0 && $0 <= 65536 }) else {
                throw PrototypeError.invalid("Invalid shape for \(record.n)")
            }
            var count = 1
            for dimension in record.shape {
                guard count <= 32 * 1024 * 1024 / dimension else { throw PrototypeError.invalid("Oversized tensor") }
                count *= dimension
            }
            let bytes = try readExactly(record.b)
            let name = record.n + (record.k == "five_value" ? ".weight" : "")
            guard weights[name] == nil else { throw PrototypeError.invalid("Duplicate tensor: \(name)") }
            if record.k == "int6" || record.k == "int8" {
                weights[name] = try decodeInteger(record, bytes: bytes, count: count)
            } else {
                weights[name] = MLXArray(try decode(record, bytes: bytes, count: count), record.shape)
            }
            if record.k == "five_value" { fiveValueCount += 1 }
        }
        guard (try handle.read(upToCount: 1))?.isEmpty != false, fiveValueCount == 264 else {
            throw PrototypeError.invalid("Unexpected trailing data or five-value tensor count")
        }
        return try mapNames(weights)
    }

    private static func decodeInteger(_ record: Record, bytes: Data, count: Int) throws -> MLXArray {
        let rows = record.shape[0], columns = count / rows
        let bits = record.k == "int6" ? 6 : 8
        let body = bits == 6 ? ((count + 3) / 4) * 3 : count
        guard bytes.count == body + rows * 2 else { throw PrototypeError.invalid("Invalid integer tensor size") }
        let values: [Float] = bytes.withUnsafeBytes { raw in
            var result = [Float](repeating: 0, count: count)
            for row in 0..<rows {
                let scale = Float(Float16(bitPattern: raw.loadUnaligned(fromByteOffset: body + row * 2, as: UInt16.self).littleEndian))
                for column in 0..<columns {
                    let index = row * columns + column
                    let q: Int
                    if bits == 6 {
                        let offset = (index / 4) * 3
                        let word = UInt32(raw[offset]) | (UInt32(raw[offset + 1]) << 8) | (UInt32(raw[offset + 2]) << 16)
                        q = Int((word >> ((index % 4) * 6)) & 63) - 32
                    } else { q = Int(Int8(bitPattern: raw[index])) }
                    result[index] = Float(q) * scale
                }
            }
            return result
        }
        return MLXArray(values, record.shape)
    }

    private static func decode(_ record: Record, bytes: Data, count: Int) throws -> [Float16] {
        try bytes.withUnsafeBytes { raw in
            func half(_ offset: Int) -> Float16 {
                Float16(bitPattern: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian)
            }
            switch record.k {
            case "fp16":
                guard bytes.count == count * 2 else { throw PrototypeError.invalid("Invalid fp16 size") }
                return (0..<count).map { half($0 * 2) }
            case "five_value":
                guard record.shape.count == 2 else { throw PrototypeError.invalid("Five-value tensor must be a matrix") }
                let rows = record.shape[0], columns = record.shape[1]
                let rowBytes = (columns + 4) / 5, signBytes = rows * rowBytes
                guard bytes.count >= signBytes + rows * 4 else { throw PrototypeError.invalid("Invalid five-value size") }
                let powers = [1, 3, 9, 27, 81]
                var nonzeroCount = 0
                for row in 0..<rows {
                    for column in 0..<columns {
                        let code = (Int(raw[row * rowBytes + column / 5]) / powers[column % 5]) % 3
                        if code != 1 { nonzeroCount += 1 }
                    }
                }
                let magnitudeBytes = (nonzeroCount + 7) / 8
                let scalesOffset = signBytes + magnitudeBytes
                guard bytes.count == scalesOffset + rows * 4 else { throw PrototypeError.invalid("Invalid five-value magnitudes") }
                var result = [Float16](repeating: 0, count: count)
                var bitIndex = 0
                for row in 0..<rows {
                    let lo = half(scalesOffset + row * 2)
                    let hi = half(scalesOffset + rows * 2 + row * 2)
                    for column in 0..<columns {
                        let code = (Int(raw[row * rowBytes + column / 5]) / powers[column % 5]) % 3
                        if code == 1 { continue }
                        let isHigh = (raw[signBytes + bitIndex / 8] >> (bitIndex % 8)) & 1 != 0
                        bitIndex += 1
                        let magnitude = isHigh ? hi : lo
                        result[row * columns + column] = code == 0 ? -magnitude : magnitude
                    }
                }
                return result
            default: throw PrototypeError.invalid("Unsupported encoding: \(record.k)")
            }
        }
    }

    private static func captures(_ pattern: String, _ key: String) -> [String]? {
        let regex = try! NSRegularExpression(pattern: "^" + pattern + "$")
        guard let match = regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: key).map { String(key[$0]) } ?? ""
        }
    }

    private static func mapNames(_ input: [String: MLXArray]) throws -> [String: MLXArray] {
        var output: [String: MLXArray] = [:]
        let attention = ["q_proj": "linear_q", "k_proj": "linear_k", "v_proj": "linear_v",
                         "o_proj": "linear_out", "relative_k_proj": "linear_pos",
                         "bias_u": "pos_bias_u", "bias_v": "pos_bias_v"]
        for (key, tensor) in input {
            if key.hasSuffix("num_batches_tracked") { continue }
            let name: String
            var value = tensor
            if let parts = captures(#"encoder\.subsampling\.layers\.(\d+)\.(weight|bias)"#, key) {
                guard ["0", "2", "3", "5", "6"].contains(parts[0]) else { throw PrototypeError.invalid("Unknown convolution") }
                name = "encoder.pre_encode.conv.\(parts[0]).\(parts[1])"
                if parts[1] == "weight" { value = tensor.transposed(0, 2, 3, 1) }
            } else if let p = captures(#"encoder\.subsampling\.linear\.(weight|bias)"#, key) {
                name = "encoder.pre_encode.out.\(p[0])"
            } else if let p = captures(#"encoder\.layers\.(\d+)\.(.+)"#, key) {
                let prefix = "encoder.layers.\(p[0]).", rest = p[1]
                if let a = captures(#"self_attn\.(\w+?)(\.weight)?"#, rest), let mapped = attention[a[0]] {
                    name = prefix + "self_attn." + mapped + a[1]
                } else if let c = captures(#"conv\.(pointwise_conv[12])\.weight"#, rest) {
                    name = prefix + "conv.\(c[0]).weight"
                    value = (tensor.ndim == 3 ? tensor : tensor.expandedDimensions(axis: 2)).transposed(0, 2, 1)
                } else if rest == "conv.depthwise_conv.weight" {
                    name = prefix + rest; value = tensor.transposed(0, 2, 1)
                } else if let n = captures(#"conv\.norm\.(weight|bias|running_mean|running_var)"#, rest) {
                    name = prefix + "conv.batch_norm.\(n[0])"
                } else if captures(#"(norm_(feed_forward[12]|self_att|conv|out)|feed_forward[12]\.linear[12])\.(weight|bias)"#, rest) != nil {
                    name = prefix + rest
                } else { throw PrototypeError.invalid("Unmapped layer: \(key)") }
            } else if let p = captures(#"encoder_projector\.(weight|bias)"#, key) { name = "joint.enc.\(p[0])"
            } else if let p = captures(#"decoder\.decoder_projector\.(weight|bias)"#, key) { name = "joint.pred.\(p[0])"
            } else if let p = captures(#"joint\.head\.(weight|bias)"#, key) { name = "joint.joint_net.2.\(p[0])"
            } else if key == "decoder.embedding.weight" { name = "decoder.prediction.embed.weight"
            } else if let p = captures(#"decoder\.lstm\.weight_(ih|hh)_l(\d+)"#, key) {
                name = "decoder.prediction.dec_rnn.lstm.\(p[1])." + (p[0] == "ih" ? "Wx" : "Wh")
            } else if let p = captures(#"decoder\.lstm\.bias_ih_l(\d+)"#, key) {
                guard let other = input["decoder.lstm.bias_hh_l\(p[0])"] else { throw PrototypeError.invalid("Missing LSTM bias") }
                name = "decoder.prediction.dec_rnn.lstm.\(p[0]).bias"
                value = (tensor.asType(.float32) + other.asType(.float32)).asType(.float16)
            } else if captures(#"decoder\.lstm\.bias_hh_l\d+"#, key) != nil { continue
            } else { throw PrototypeError.invalid("Unmapped tensor: \(key)") }
            guard output[name] == nil else { throw PrototypeError.invalid("Duplicate mapped tensor") }
            output[name] = value
        }
        guard output.count == 697 else { throw PrototypeError.invalid("Expected 697 mapped tensors, got \(output.count)") }
        return output
    }
}
