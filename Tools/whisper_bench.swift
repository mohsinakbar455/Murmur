#!/usr/bin/env swift
/// Tools/whisper_bench.swift
///
/// Standalone Whisper multi-model file benchmark for Murmur.
///
/// Run after downloading Whisper models through the File Transcription UI:
///
///   swift Tools/whisper_bench.swift /tmp/murmur_test_speech.wav
///   swift Tools/whisper_bench.swift ~/Desktop/myrecording.m4a
///
/// Output: wall-clock process time, realtime factor, and raw transcript for each model.
/// Models are tested one at a time; the previous model is unloaded from RAM before loading
/// the next one (matching WhisperKitPool's single-model constraint in the main app).
///
/// IMPORTANT: This file is for quick CLI use. It imports WhisperKit via the resolved
/// package cache produced by `make build`. Run `make build` first.

import Foundation
import WhisperKit
import AVFoundation

// MARK: - Config

/// Whisper models to bench, in order. Only installed models are tested.
let models: [(id: String, variant: String, label: String)] = [
    ("whisper-large-v3",       "openai_whisper-large-v3",       "Maximum Accuracy"),
    ("whisper-large-v3-turbo", "openai_whisper-large-v3_turbo", "Fast + Accurate"),
    ("whisper-medium",         "openai_whisper-medium",          "Balanced"),
    ("whisper-small",          "openai_whisper-small",           "Lightweight"),
]

let downloadBase: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Murmur/WhisperModels", isDirectory: true)
}()

// MARK: - Helpers

func modelFolder(variant: String) -> URL {
    downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(variant)", isDirectory: true)
}

func isInstalled(variant: String) -> Bool {
    let dir = modelFolder(variant: variant)
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir.path) else { return false }
    let hasEncoder = fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlmodelc").path)
    let hasMel    = fm.fileExists(atPath: dir.appendingPathComponent("MelSpectrogram.mlmodelc").path)
    let hasDecoder = fm.fileExists(atPath: dir.appendingPathComponent("TextDecoder.mlmodelc").path)
    return hasEncoder && hasMel && hasDecoder
}

func audioDuration(url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else {
        return Double(0)
    }
    return Double(file.length) / file.fileFormat.sampleRate
}

// MARK: - Main

guard CommandLine.arguments.count > 1 else {
    print("usage: swift Tools/whisper_bench.swift <audio_file>")
    print("")
    print("Download Whisper models first via the Murmur app File Transcription panel,")
    print("or with `make build` followed by using the app's model download UI.")
    exit(1)
}

let audioPath = CommandLine.arguments[1]
let audioURL = URL(fileURLWithPath: audioPath)

guard FileManager.default.fileExists(atPath: audioURL.path) else {
    print("error: file not found: \(audioPath)")
    exit(1)
}

let duration = audioDuration(url: audioURL)
print("═══════════════════════════════════════════════════════════")
print("Murmur · Whisper Multi-Model Benchmark")
print("Audio  : \(audioURL.lastPathComponent) (\(String(format: "%.2f", duration))s)")
print("Date   : \(Date())")
print("═══════════════════════════════════════════════════════════\n")

// Load audio samples once — all Whisper models share the same input
print("Loading audio samples…")
let samples: [Float]
do {
    samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
} catch {
    print("error: failed to load audio: \(error)")
    exit(1)
}
print("Loaded \(samples.count) samples (16kHz mono)\n")

var anyRan = false

for model in models {
    guard isInstalled(variant: model.variant) else {
        print("⚠  \(model.id) [\(model.label)]")
        print("   Not installed — skipping. Download via Murmur app → File Transcription → Voice Models.\n")
        continue
    }

    anyRan = true
    print("▸  \(model.id) [\(model.label)]")

    let dir = modelFolder(variant: model.variant)

    let loadStart = Date()
    do {
        let kit = try await WhisperKit(modelFolder: dir.path, download: false)
        let loadSeconds = Date().timeIntervalSince(loadStart)

        var options = DecodingOptions(verbose: false)
        options.language = nil  // auto-detect

        let processStart = Date()
        let result = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let processSeconds = Date().timeIntervalSince(processStart)

        let text = result.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let realtimeFactor = duration / max(processSeconds, 0.0001)

        print(String(format: "   Load   : %.2fs", loadSeconds))
        print(String(format: "   Process: %.2fs  (%.0f× realtime)", processSeconds, realtimeFactor))
        print("   Transcript:")
        print("   \(text)\n")

    } catch {
        print("   ERROR: \(error.localizedDescription)\n")
    }
}

if !anyRan {
    print("No Whisper models are installed.")
    print("")
    print("Download models from within the app:")
    print("  1. Launch Murmur")
    print("  2. Navigate to File Transcription in the sidebar")
    print("  3. Select a Whisper model from the dropdown")
    print("  4. Click 'Download Model' in the uninstalled banner")
}

print("═══════════════════════════════════════════════════════════")
print("Done.")
