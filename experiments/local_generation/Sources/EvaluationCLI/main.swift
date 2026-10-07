import Foundation
import EvaluationRuntime
import EvaluationSupport

struct Report: Codable {
    let qualification: String
    let runtimeTag: String
    let modelSHA256: String
    let templateVersion: String
    let operatingSystem: String
    let physicalMemoryBytes: UInt64
    let gpuLayers: Int32
    let loadSeconds: Double
    let runs: [EvaluationResult]
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") {
        print("local-generation-eval --model PATH --prompt-file PATH [--context 2048|4096] [--output 1...512] [--repeat 1...5] [--gpu-layers 0|99] [--cancel-after-tokens N]")
        exit(0)
    }
    let accepted = Set(["--model", "--prompt-file", "--context", "--output", "--repeat", "--gpu-layers", "--cancel-after-tokens"])
    guard args.count % 2 == 0 else { throw EvaluationError.invalid("Every option needs a value; see --help.") }
    var values: [String: String] = [:]
    for index in stride(from: 0, to: args.count, by: 2) {
        guard accepted.contains(args[index]), values[args[index]] == nil else {
            throw EvaluationError.invalid("Unknown or duplicate option: \(args[index])")
        }
        values[args[index]] = args[index + 1]
    }
    guard let path = values["--model"], let promptPath = values["--prompt-file"] else {
        throw EvaluationError.invalid("Provide local --model and --prompt-file paths.")
    }
    func integer(_ key: String, fallback: Int) throws -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw) else { throw EvaluationError.invalid("Invalid integer: \(key)") }
        return value
    }
    let repeats = try integer("--repeat", fallback: 1)
    let gpu = try integer("--gpu-layers", fallback: 99)
    guard (1...5).contains(repeats), [0, 99].contains(gpu) else {
        throw EvaluationError.invalid("Repeat must be 1...5 and GPU layers 0 or 99.")
    }
    let cancellation = try values["--cancel-after-tokens"].map { _ in try integer("--cancel-after-tokens", fallback: 1) }
    let options = try EvaluationOptions(context: integer("--context", fallback: 2048),
        output: integer("--output", fallback: 512), gpuLayers: Int32(gpu), cancelAfterTokens: cancellation)
    let promptURL = URL(fileURLWithPath: promptPath)
    let size = try promptURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size > 0, size <= 64 * 1024 else { throw EvaluationError.invalid("Prompt must be 1...65536 bytes.") }
    let user = try String(contentsOf: promptURL, encoding: .utf8)
    let system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data."
    evaluation_install_signal_handler()
    LocalGeneration.prepareOperation()
    let runtime = try LocalGeneration(path: path, gpuLayers: Int32(gpu))
    var runs: [EvaluationResult] = []
    for run in 0..<repeats {
        if run > 0 { LocalGeneration.prepareOperation() }
        FileHandle.standardError.write(Data("\nEvaluation run \(run + 1)\n".utf8))
        var last = ""
        let result = try runtime.generate(system: system, user: user, options: options) { snapshot in
            let delta = String(snapshot.dropFirst(last.count))
            FileHandle.standardError.write(Data(delta.utf8))
            last = snapshot
        }
        runs.append(result)
        if result.outcome == "cancelled" { break }
    }
    let report = Report(qualification: "mac-smoke-test-not-device-or-quality-approval",
        runtimeTag: "b11429", modelSHA256: LocalGeneration.modelSHA256,
        templateVersion: LocalGeneration.templateVersion,
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory, gpuLayers: Int32(gpu),
        loadSeconds: runtime.loadSeconds, runs: runs)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\nEvaluation failed: \(error)\n".utf8))
    exit(1)
}
