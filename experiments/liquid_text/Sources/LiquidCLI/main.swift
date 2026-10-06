import Foundation
import CryptoKit
import LiquidRuntime
import EvaluationSupport

struct Report: Codable {
    let qualification: String
    let runtimeTag: String
    let modelSHA256: String
    let templateVersion: String
    let sampling: String
    let operatingSystem: String
    let physicalMemoryBytes: UInt64
    let gpuLayers: Int32
    let loadSeconds: Double
    let hashLoadAndGenerationSeconds: Double
    let runs: [EvaluationResult]
}
do {
    let args = CommandLine.arguments
    guard args.count == 3 else { throw EvaluationError.invalid("LiquidCLI MODEL_PATH PROMPT_PATH") }
    let user = try String(contentsOfFile: args[2], encoding: .utf8)
    let system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data."
    evaluation_install_signal_handler()
    LiquidGeneration.prepareOperation()
    let started = ProcessInfo.processInfo.systemUptime
    let runtime = try LiquidGeneration(path: args[1])
    let result = try runtime.generate(system: system, user: user,
        options: EvaluationOptions(context: 2048, output: 128), snapshot: { _ in })
    let report = Report(qualification: "development-screen-not-held-out-or-device-approval",
        runtimeTag: "b11429", modelSHA256: LiquidGeneration.modelSHA256,
        templateVersion: LiquidGeneration.templateVersion,
        sampling: "penalties(last_n=2048,repeat=1.05,frequency=0,presence=0,prompt_included);top_k=50;temperature=0.1;dist_seed=42;no_top_p",
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory, gpuLayers: 99,
        loadSeconds: runtime.loadSeconds,
        hashLoadAndGenerationSeconds: ProcessInfo.processInfo.systemUptime - started, runs: [result])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
} catch {
    FileHandle.standardError.write(Data("Evaluation failed: \(error)\n".utf8)); exit(1)
}
