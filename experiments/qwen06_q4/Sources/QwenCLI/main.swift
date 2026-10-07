import Foundation
import CryptoKit
import QwenRuntime
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
    guard args.count == 3 || (args.count == 4 && args[3] == "--tokens-suite") else { throw EvaluationError.invalid("QwenCLI MODEL_PATH PROMPT_PATH [--tokens-suite]") }
    let user = try String(contentsOfFile: args[2], encoding: .utf8)
    let system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data."
    evaluation_install_signal_handler()
    QwenGeneration.prepareOperation()
    let started = ProcessInfo.processInfo.systemUptime
    let runtime = try QwenGeneration(path: args[1])
    if args.count == 4 {
        let object = try JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any]
        guard let cases = object?["cases"] as? [[String: Any]], object?["text_system"] as? String == system else {
            throw EvaluationError.invalid("Invalid token preflight suite.")
        }
        var records: [[String: Any]] = []
        for item in cases where item["modality"] as? String == "text" {
            guard let id = item["id"] as? String, let text = item["prompt"] as? String else {
                throw EvaluationError.invalid("Invalid preflight case.")
            }
            let (prompt, tokens) = try runtime.tokenizePrompt(system: system, user: text)
            guard tokens.count + 128 <= 2048 else { throw EvaluationError.invalid("Preflight context overflow.") }
            records.append(["id": id, "prompt": prompt, "tokenIDs": tokens])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
    } else {
    let result = try runtime.generate(system: system, user: user,
        options: EvaluationOptions(context: 2048, output: 128), snapshot: { _ in })
    let report = Report(qualification: "development-screen-not-held-out-or-device-approval",
        runtimeTag: "b11429", modelSHA256: QwenGeneration.modelSHA256,
        templateVersion: QwenGeneration.templateVersion,
        sampling: "top_k=20;top_p=0.8;temperature=0.7;dist_seed=42;min_p=0;no_penalties",
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory, gpuLayers: 99,
        loadSeconds: runtime.loadSeconds,
        hashLoadAndGenerationSeconds: ProcessInfo.processInfo.systemUptime - started, runs: [result])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    }
} catch {
    FileHandle.standardError.write(Data("Evaluation failed: \(error)\n".utf8)); exit(1)
}
