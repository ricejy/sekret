// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Qwen06Q4TextEvaluation",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "QwenRuntime", targets: ["QwenRuntime"])],
    targets: [
        .binaryTarget(name: "llama", path: "artifacts/llama.xcframework"),
        .target(name: "EvaluationSupport", publicHeadersPath: "include"),
        .target(name: "QwenRuntime", dependencies: ["llama", "EvaluationSupport"]),
        .executableTarget(name: "QwenCLI", dependencies: ["QwenRuntime", "EvaluationSupport"]),
        .testTarget(name: "QwenRuntimeTests", dependencies: ["QwenRuntime"]),
    ], swiftLanguageModes: [.v5]
)
