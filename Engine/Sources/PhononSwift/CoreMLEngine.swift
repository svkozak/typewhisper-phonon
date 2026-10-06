import Foundation
import PhononCoreML

/// The helper owns one transcriber and calls it from its serial request loop.
enum CoreMLEngine {
    static func load(cache: URL, statusFile: URL) throws -> Transcriber {
        let directory = try ModelStore.prepare(cache: cache, statusFile: statusFile)
        ModelStore.status("Loading Phonon-2…", file: statusFile)
        var options = Transcriber.Options()
        options.computeUnits = .cpuAndNeuralEngine
        // Keep encoder windows and decoder jobs serial inside each request too.
        options.decoderWorkers = 1
        options.encoderInFlight = 1
        options.backgroundLoad = false
        // Version 1.1.1 adds 20 ms when selecting an encoder function. Keep
        // windows below the exact 15/35 s limits so full windows fit and the
        // 35 s boundary never produces an "exceeds largest function" error.
        options.singleShotMaxSeconds = 34.9
        options.windowSeconds = 14.9
        // Prepare every supported window before reporting readiness. Otherwise a
        // first dictation could block while Core ML prepares a different window.
        options.eagerFunctions = [5, 10, 15, 35]
        options.progress = { phase, seconds in
            ModelStore.status("Preparing Phonon-2 (first setup can take several minutes)…", file: statusFile)
            FileHandle.standardError.write(Data("[phonon-swift] Core ML: \(phase) (\(Int(seconds)) seconds)\n".utf8))
        }
        let model = try Transcriber(bundle: directory, options: options)
        ModelStore.status("Phonon-2 is ready", file: statusFile)
        return model
    }

    static func transcribe(_ samples: [Float], using model: Transcriber) throws -> String {
        // The upstream frontend needs at least two 10 ms frames for variance
        // normalization. A shorter recording cannot contain a complete word.
        guard samples.count >= 320 else { return "" }
        return try model.transcribe(samples).text
    }
}
