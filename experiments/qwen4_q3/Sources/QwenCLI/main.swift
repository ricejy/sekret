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
    guard args.count == 3 || (args.count == 4 && ["--tokens-suite", "--output-512"].contains(args[3])) else { throw EvaluationError.invalid("QwenCLI MODEL_PATH PROMPT_PATH [--tokens-suite|--output-512]") }
    let boundaryCheck = args[2] == "--boundary-check"
    let user = boundaryCheck ? "" : try String(contentsOfFile: args[2], encoding: .utf8)
    let system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data."
    evaluation_install_signal_handler()
    QwenGeneration.prepareOperation()
    let started = ProcessInfo.processInfo.systemUptime
    let runtime = try QwenGeneration(path: args[1])
    if boundaryCheck {
        var records: [[String: Any]] = []
        for (index, context) in [2048, 4096].enumerated() {
            let (_, admitted) = try runtime.tokenizePrompt(system: system, user: PacedChatFixture.boundaryBriefs[index])
            let (_, rejected) = try runtime.tokenizePrompt(system: system, user: PacedChatFixture.overflowingBriefs[index])
            guard admitted.count == [1884, 3938][index], rejected.count == [1922, 3977][index],
                  admitted.count + 128 <= context, rejected.count + 128 > context else {
                throw EvaluationError.invalid("Boundary fixture token counts changed.")
            }
            var overflowRejected = false
            do {
                _ = try runtime.generate(system: system, user: PacedChatFixture.overflowingBriefs[index],
                    options: EvaluationOptions(context: context, output: 128), snapshot: { _ in })
            } catch {
                overflowRejected = String(describing: error) == "Exact templated input plus output reservation exceeds context; no truncation."
            }
            guard overflowRejected else { throw EvaluationError.invalid("Context overflow was not correctly rejected.") }
            records.append(["context": context, "admittedInputTokens": admitted.count,
                "overflowInputTokens": rejected.count, "outputReservation": 128, "overflowRejectedBeforeGeneration": true])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
    } else if args.last == "--tokens-suite" {
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
        options: EvaluationOptions(context: 2048, output: args.last == "--output-512" ? 512 : 128), snapshot: { _ in })
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
