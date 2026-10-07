// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SekretLocalGenerationEvaluation",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "local-generation-eval", targets: ["EvaluationCLI"]),
        .library(name: "EvaluationRuntime", targets: ["EvaluationRuntime"]),
    ],
    targets: [
        .binaryTarget(name: "llama", path: "artifacts/build-apple/llama.xcframework"),
        .target(name: "EvaluationSupport", publicHeadersPath: "include"),
        .target(name: "EvaluationRuntime", dependencies: ["llama", "EvaluationSupport"]),
        .executableTarget(name: "EvaluationCLI", dependencies: ["EvaluationRuntime", "EvaluationSupport"]),
        .testTarget(name: "EvaluationRuntimeTests", dependencies: ["EvaluationRuntime"]),
    ],
    swiftLanguageModes: [.v5]
)
