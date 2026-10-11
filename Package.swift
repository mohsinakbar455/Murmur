// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet TDT as CoreML on the Neural Engine. Optional at runtime — Apple's
        // SpeechTranscriber remains the default and needs no dependency at all.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0")
    ],
    targets: [
        // The dictionary is its own target so it can be tested directly, and because its
        // behaviour is a cross-platform contract: the Windows app reimplements this logic in
        // C#, and both sides run the same vectors in shared/dictionary-test-vectors.json.
        .target(
            name: "MurmurDictionary",
            path: "Sources/MurmurDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Murmur",
            dependencies: [
                "MurmurDictionary",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Murmur",
            resources: [.copy("Resources/Humanizer-LICENSE.txt")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("MURMUR_HAS_LIQUID_GLASS"),
            ]
        ),
        .testTarget(
            name: "MurmurDictionaryTests",
            dependencies: ["MurmurDictionary"],
            path: "Tests/MurmurDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MurmurTests",
            dependencies: [
                "Murmur",
                "MurmurDictionary",
            ],
            path: "Tests/MurmurTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("MURMUR_HAS_LIQUID_GLASS"),
            ]
        ),
    ]
)
