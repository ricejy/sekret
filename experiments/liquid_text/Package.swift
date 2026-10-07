// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LiquidTextEvaluation",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(name: "llama", path: "artifacts/llama.xcframework"),
        .target(name: "EvaluationSupport", publicHeadersPath: "include"),
        .target(name: "LiquidRuntime", dependencies: ["llama", "EvaluationSupport"]),
        .executableTarget(name: "LiquidCLI", dependencies: ["LiquidRuntime", "EvaluationSupport"]),
        .testTarget(name: "LiquidRuntimeTests", dependencies: ["LiquidRuntime"]),
    ],
    swiftLanguageModes: [.v5]
)
