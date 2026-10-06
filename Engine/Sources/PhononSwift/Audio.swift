import AVFoundation
import Foundation

/// Convert decoded mono samples in memory. Never use FileSource, which writes a
/// temporary audio file when resampling. The helper calls this synchronously.
func resampleAudio(_ samples: [Float], from rate: Int, to target: Int) throws -> [Float] {
    guard !samples.isEmpty,
          let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false),
          let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(target), channels: 1, interleaved: false),
          let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
          let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
        throw PrototypeError.invalid("Cannot convert WAV audio to 16 kHz mono")
    }
    input.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
    converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    let feed = AudioConverterInput(input)
    let expected = Int((Double(samples.count) * Double(target) / Double(rate)).rounded())
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(min(expected + 4096, 65536))) else {
        throw PrototypeError.invalid("Cannot allocate converted audio")
    }
    var result: [Float] = []
    result.reserveCapacity(expected)
    while true {
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in feed.next(state) }
        guard status != .error else { throw PrototypeError.invalid("Cannot resample WAV audio") }
        let count = min(Int(output.frameLength), max(0, expected - result.count))
        if count > 0 { result.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: count)) }
        if status == .endOfStream || (status == .inputRanDry && output.frameLength == 0) { break }
    }
    guard result.count == expected, !result.isEmpty, result.allSatisfy(\.isFinite) else {
        throw PrototypeError.invalid("WAV conversion did not produce valid audio")
    }
    return result
}

// AVAudioConverter invokes its input callback synchronously during convert().
// The buffer and supplied flag stay confined to that call on the helper thread.
private final class AudioConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if supplied { state.pointee = .endOfStream; return nil }
        supplied = true
        state.pointee = .haveData
        return buffer
    }
}
