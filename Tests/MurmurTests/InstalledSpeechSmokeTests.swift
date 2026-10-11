import Foundation
import Testing
@testable import Murmur

/// Explicitly opt-in: the caller supplies a synthetic local audio fixture and an
/// already-installed model. This test never opens a microphone or installs assets.
@Suite("Installed speech integration smoke check")
struct InstalledSpeechSmokeTests {
    @Test("An installed local speech model decodes a supplied synthetic fixture",
          .enabled(if: ProcessInfo.processInfo.environment["MURMUR_SPEECH_SMOKE_AUDIO"] != nil
                   && ProcessInfo.processInfo.environment["MURMUR_SPEECH_SMOKE_MODEL"] != nil))
    func decodeInstalledModel() async throws {
        let environment = ProcessInfo.processInfo.environment
        let audioPath = try #require(environment["MURMUR_SPEECH_SMOKE_AUDIO"])
        let modelID = try #require(environment["MURMUR_SPEECH_SMOKE_MODEL"])
        let audioURL = URL(fileURLWithPath: audioPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: audioURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            Issue.record("MURMUR_SPEECH_SMOKE_AUDIO must name an existing local synthetic audio file.")
            return
        }

        // Do not call prepare until this check passes: Apple manages its own assets,
        // and missing downloadable models are intentionally outside this test's scope.
        let installed: Bool
        if ["parakeet-v2", "parakeet-v3", "parakeet-110m"].contains(modelID) {
            installed = ParakeetModels.isVersionDownloaded(SpeechRecognitionService.parakeetVersion(for: modelID))
        } else if modelID.hasPrefix("whisper"), WhisperModelsCatalog.spec(for: modelID) != nil {
            installed = WhisperKitPool.isModelCompleteOnDisk(modelID: modelID)
        } else {
            Issue.record("Use an installed Parakeet or Whisper model. Apple Speech and unknown model IDs are excluded to prevent implicit asset installation.")
            return
        }
        guard installed else {
            Issue.record("The requested speech model is not fully installed. This smoke check will not download it: \(modelID)")
            return
        }

        let (samples, _) = try UniversalAudioLoader.loadAudioSamples(from: audioURL)
        try #require(!samples.isEmpty, "The synthetic fixture must contain decodable audio.")
        let preparationStart = Date()
        try await SpeechRecognitionService.shared.prepare(modelID: modelID)
        let preparationSeconds = Date().timeIntervalSince(preparationStart)
        let requiredTerms = (environment["MURMUR_SPEECH_SMOKE_EXPECT_TERMS"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        print("Synthetic speech smoke check — model: \(modelID)")
        print(String(format: "Preparation: %.3f s", preparationSeconds))
        for pass in 1...2 {
            let decodeStart = Date()
            let text = try await SpeechRecognitionService.shared.transcribe(samples: samples, modelID: modelID,
                language: environment["MURMUR_SPEECH_SMOKE_LANGUAGE"],
                vocabulary: (environment["MURMUR_SPEECH_SMOKE_VOCABULARY"] ?? "").split(separator: ",").map(String.init))
            let decodeSeconds = Date().timeIntervalSince(decodeStart)
            print(String(format: "Decode pass %d: %.3f s", pass, decodeSeconds))
            print("Synthetic fixture transcript (pass \(pass)): \(text)")
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "The installed model should return nonempty text for the supplied synthetic speech.")
            for term in requiredTerms {
                let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: term) + #"(?![\p{L}\p{N}])"#
                #expect(text.range(of: pattern, options: .regularExpression) != nil,
                        "The synthetic fixture should retain the explicitly expected term: \(term)")
            }
        }
    }
}
