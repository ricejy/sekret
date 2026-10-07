// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Qwen4TextEvaluation",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "llama", path: "artifacts/llama.xcframework"),
        .target(name: "EvaluationSupport", publicHeadersPath: "include"),
        .target(name: "QwenRuntime", dependencies: ["llama", "EvaluationSupport"]),
        .executableTarget(name: "QwenCLI", dependencies: ["QwenRuntime", "EvaluationSupport"]),
        .testTarget(name: "QwenRuntimeTests", dependencies: ["QwenRuntime"]),
    ], swiftLanguageModes: [.v5]
)
