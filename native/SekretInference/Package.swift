// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SekretInference",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SekretInference", targets: ["SekretInference"])],
    targets: [
        .binaryTarget(name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11429/llama-b11429-xcframework.zip",
            checksum: "e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174"),
        .target(name: "RuntimeSupport", publicHeadersPath: "include"),
        .target(name: "SekretInference", dependencies: ["llama", "RuntimeSupport"]),
        .testTarget(name: "SekretInferenceTests", dependencies: ["SekretInference"], resources: [.copy("Fixtures")]),
    ], swiftLanguageModes: [.v5]
)
