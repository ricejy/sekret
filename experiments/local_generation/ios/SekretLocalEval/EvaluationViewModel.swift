import Foundation
import SwiftUI
import EvaluationRuntime

struct PhoneReport: Encodable {
    let qualification = "unqualified-physical-device-evaluation"
    let runtime = "llama.cpp-b11429"
    let modelSHA256 = LocalGeneration.modelSHA256
    let templateVersion = LocalGeneration.templateVersion
    let operatingSystem: String
    let physicalMemoryBytes: UInt64
    let loadSeconds: Double
    let result: EvaluationResult
}

@MainActor
final class EvaluationViewModel: ObservableObject {
    @Published private(set) var status = "Import the pinned local GGUF to begin."
    @Published private(set) var output = ""
    @Published private(set) var busy = false
    @Published private(set) var hasModel = false
    @Published private(set) var exportURL: URL?
    @Published private(set) var stopToReturnSeconds: Double?
    @Published var context = 2048
    @Published var selectedPrompt = 0

    private var operation: UUID?
    private var stopRequestedAt: TimeInterval?
    private var worker: Task<Void, Never>?
    private var foreground = true
    private var launchedSuite = false
    private let directory: URL
    private var modelURL: URL { directory.appendingPathComponent("Qwen3-0.6B-Q8_0.gguf") }

    static let prompts = [
        "Give three concise suggestions for organizing a fictional neighborhood seed exchange. Do not name real people or businesses.",
        "Fictional notice: The Alder Club meets Thursday at 18:30 in Room Cedar. On festival week only, it meets Friday at 17:00 instead. Restate the ordinary meeting and the exception in two sentences.",
        "Write one short French sentence including café and été, followed by one short Korean greeting. This is fictional Unicode test text.",
        "Write a long fictional story about a robot organizing imaginary seeds, continuing until the output limit. This is a Stop-button test, not a quality benchmark.",
    ]

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SekretLocalEvaluation", isDirectory: true)
        // This also prepares the isolated destination for an explicitly
        // authorized devicectl transfer; every run still verifies the hash.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protectedDirectory = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try? protectedDirectory.setResourceValues(flags)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        hasModel = FileManager.default.fileExists(atPath: modelURL.path)
        if hasModel { status = "Local artifact found. Its full hash is checked before every run." }
    }

    private func begin(_ message: String) -> UUID? {
        guard !busy, foreground else { return nil }
        LocalGeneration.prepareOperation()
        let id = UUID()
        operation = id
        busy = true
        status = message
        stopRequestedAt = nil
        stopToReturnSeconds = nil
        exportURL = nil
        output = ""
        return id
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value { stop(reason: "App left foreground") }
        if value { runRequestedSuite() }
    }

    /// Fixed fictional probes only; no model URL or arbitrary prompt arguments.
    private func runRequestedSuite() {
        guard !launchedSuite, CommandLine.arguments.contains("--evaluation-suite"), hasModel,
              let id = begin("Running the fixed fictional phone evaluation suite…") else { return }
        launchedSuite = true
        let path = modelURL.path
        let fixedPrompts = Self.prompts
        let reports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EvaluationReports", isDirectory: true)
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
                let plans: [(String, Int, Int, Int?)] = [
                    ("phone-2k-1", 2048, 0, nil),
                    ("phone-2k-2", 2048, 0, nil),
                    ("phone-4k-1", 4096, 0, nil),
                    ("phone-4k-2", 4096, 0, nil),
                    ("phone-fictional-facts", 2048, 1, nil),
                    ("phone-unicode", 2048, 2, nil),
                    ("phone-cancel-8", 2048, 0, 8),
                ]
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var completed: [String] = []
                for (name, context, promptIndex, cancelAt) in plans {
                    if LocalGeneration.isCancellationRequested { break }
                    await MainActor.run { [weak self] in self?.status = "Running \(name)…" }
                    let report = try Self.performRun(path: path, prompt: fixedPrompts[promptIndex],
                        context: context, output: 128, cancelAfterTokens: cancelAt) { snapshot in
                        Task { @MainActor [weak self] in
                            guard self?.operation == id else { return }
                            self?.output = snapshot
                        }
                    }
                    try encoder.encode(report).write(to: reports.appendingPathComponent(name + ".json"),
                        options: [.atomic, .completeFileProtection])
                    completed.append(name)
                }
                let terminal: [String: Any] = ["completedProbes": completed,
                    "cancellationRequested": LocalGeneration.isCancellationRequested,
                    "qualification": "smoke-only-not-release-approval"]
                try JSONSerialization.data(withJSONObject: terminal, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reports.appendingPathComponent("suite-complete.json"), options: [.atomic, .completeFileProtection])
                await self?.finish(id: id, message: "Fixed suite finished: \(completed.count) probes. Reports are local.")
            } catch {
                let terminal = ["error": String(describing: error), "qualification": "incomplete-evaluation"]
                try? JSONSerialization.data(withJSONObject: terminal, options: [.prettyPrinted])
                    .write(to: reports.appendingPathComponent("suite-failed.json"), options: [.atomic, .completeFileProtection])
                await self?.finish(id: id, message: "Suite ended: \(error)")
            }
        }
    }

    func stop(reason: String = "Stop tapped") {
        guard busy else { return }
        if stopRequestedAt == nil { stopRequestedAt = ProcessInfo.processInfo.systemUptime }
        LocalGeneration.requestCancellation()
        status = "\(reason): cancellation requested; waiting for native completion."
        // Do not drop/cancel the Swift task: native cleanup must return before
        // another operation is admitted. Metal checks occur between batches.
    }

    func importModel(from source: URL) {
        guard let id = begin("Copying and verifying the pinned artifact…") else { return }
        let destination = modelURL
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try Self.copyVerified(source: source, destination: destination)
                await self?.finish(id: id, message: "Model verified and stored locally.", imported: true)
            } catch {
                await self?.finish(id: id, message: "Import ended: \(error)")
            }
        }
    }

    func run() {
        guard hasModel, let id = begin("Verifying model and loading native runtime…") else { return }
        let path = modelURL.path
        let prompt = Self.prompts[selectedPrompt]
        let contextSize = context
        let reportDirectory = directory
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let report = try Self.performRun(path: path, prompt: prompt, context: contextSize) { snapshot in
                    Task { @MainActor [weak self] in
                        guard self?.operation == id else { return }
                        self?.output = snapshot
                        if self?.stopRequestedAt == nil { self?.status = "Generating locally…" }
                    }
                }
                // performRun has returned and released context/model before
                // finish enables another run. This is real native completion.
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let url = reportDirectory.appendingPathComponent("evaluation-\(id.uuidString).json")
                try encoder.encode(report).write(to: url, options: [.atomic, .completeFileProtection])
                await self?.finish(id: id, message: "\(report.result.outcome): \(report.result.outputTokens) output tokens. Not quality approval.", report: report, export: url)
            } catch {
                await self?.finish(id: id, message: "Evaluation ended: \(error)")
            }
        }
    }

    private func finish(id: UUID, message: String, imported: Bool = false,
                        report: PhoneReport? = nil, export: URL? = nil) {
        guard operation == id else { return }
        if let start = stopRequestedAt {
            stopToReturnSeconds = ProcessInfo.processInfo.systemUptime - start
        }
        operation = nil
        worker = nil
        busy = false
        status = message
        if imported { hasModel = true }
        if let report { output = report.result.response }
        exportURL = export
    }

    nonisolated private static func performRun(path: String, prompt: String, context: Int,
                                               output: Int = 512, cancelAfterTokens: Int? = nil,
                                               snapshot: (String) -> Void) throws -> PhoneReport {
        try autoreleasepool {
            let runtime = try LocalGeneration(path: path)
            let options = try EvaluationOptions(context: context, output: output, cancelAfterTokens: cancelAfterTokens)
            let result = try runtime.generate(
                system: "You are a concise on-device assistant. Answer directly using fictional evaluation text.",
                user: prompt, options: options, snapshot: snapshot)
            return PhoneReport(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                loadSeconds: runtime.loadSeconds, result: result)
        }
    }

    nonisolated private static func copyVerified(source: URL, destination: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == LocalGeneration.modelBytes else {
            throw EvaluationError.invalid("Choose the pinned 639,446,688-byte Qwen GGUF.")
        }
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var protectedFolder = folder
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try protectedFolder.setResourceValues(flags)
        let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard available > Int64(LocalGeneration.modelBytes) + 128 * 1024 * 1024 else {
            throw EvaluationError.invalid("Not enough reported free space for staged import plus reserve.")
        }
        let staged = folder.appendingPathComponent("\(UUID().uuidString).part")
        guard FileManager.default.createFile(atPath: staged.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw EvaluationError.invalid("Could not create staging file.")
        }
        defer { try? FileManager.default.removeItem(at: staged) }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: staged)
        defer { try? input.close(); try? output.close() }
        var written: UInt64 = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if LocalGeneration.isCancellationRequested { throw EvaluationError.cancelled }
            written += UInt64(chunk.count)
            guard written <= LocalGeneration.modelBytes else { throw EvaluationError.invalid("Artifact grew during import.") }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        try LocalGeneration.verifyModel(path: staged.path)
        if LocalGeneration.isCancellationRequested { throw EvaluationError.cancelled }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: destination)
        }
    }
}
