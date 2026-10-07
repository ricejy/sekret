import Foundation
import SwiftUI
import UIKit
import QwenRuntime

struct PhoneReport: Encodable {
    let qualification = "unqualified-physical-device-evaluation"
    let runtime = "llama.cpp-b11429"
    let modelSHA256 = QwenGeneration.modelSHA256
    let templateVersion: String
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
    private var stopReason: String?
    private var worker: Task<Void, Never>?
    private var foreground = true
    private var launchedSuite = false
    private var priorIdleTimerDisabled: Bool?
    private let directory: URL
    private var modelURL: URL { directory.appendingPathComponent("Qwen3-4B-Instruct-2507-Q3_K_M.gguf") }

    static let prompts = [
        "Give three concise suggestions for organizing a fictional neighborhood seed exchange. Do not name real people or businesses.",
        "Fictional notice: The Alder Club meets Thursday at 18:30 in Room Cedar. On festival week only, it meets Friday at 17:00 instead. Restate the ordinary meeting and the exception in two sentences.",
        "Write one short French sentence including café and été, followed by one short Korean greeting. This is fictional Unicode test text.",
        // Old output-limit wording produced a reproducible refusal; evidence retained.
        PacedChatFixture.story,
    ]

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SekretQwen4Q3Evaluation", isDirectory: true)
        // This also prepares the isolated destination for an explicitly
        // authorized devicectl transfer; every run still verifies the hash.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protectedDirectory = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try? protectedDirectory.setResourceValues(flags)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        if CommandLine.arguments.contains("--manual-long-probe") { selectedPrompt = 3 }
        hasModel = FileManager.default.fileExists(atPath: modelURL.path)
        if hasModel { status = "Local artifact found. Its full hash is checked before every run." }
        let readiness: [String: Any] = [
            "availableDiskBytes": (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? -1,
            "availableMemoryBytes": QwenGeneration.availableMemoryBytes,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "batteryLevel": UIDevice.current.batteryLevel,
            "batteryState": UIDevice.current.batteryState.rawValue,
            "brightness": UIScreen.main.brightness,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "modelPresent": hasModel,
            "modelSHA256": QwenGeneration.modelSHA256,
            "time": ISO8601DateFormatter().string(from: Date())]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: readiness, options: [.prettyPrinted, .sortedKeys])
            .write(to: documents.appendingPathComponent("q3-readiness.json"), options: [.atomic, .completeFileProtection])
    }

    private func begin(_ message: String) -> UUID? {
        guard !busy, foreground else { return nil }
        if CommandLine.arguments.contains("--power-profile") {
            guard powerAdmissionAllowed() else {
                status = "Power pilot needs unplugged battery ≥30%, nominal thermals, and Low Power Mode off. No inference started."
                return nil
            }
            priorIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        guard ProcessInfo.processInfo.thermalState.rawValue < 2 else {
            status = "Device needs to cool before evaluation can start. Please try again later."
            return nil
        }
        QwenGeneration.prepareOperation()
        let id = UUID()
        operation = id
        busy = true
        status = message
        stopRequestedAt = nil
        stopReason = nil
        stopToReturnSeconds = nil
        exportURL = nil
        output = ""
        return id
    }

    private func powerAdmissionAllowed() -> Bool {
        let battery = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let allowed = state == .unplugged && battery >= 0.3 && thermal == .nominal && !lowPower
        let receipt: [String: Any] = ["allowed": allowed, "unixTime": Date().timeIntervalSince1970,
            "batteryLevel": battery, "batteryState": state.rawValue, "thermalState": thermal.rawValue,
            "lowPowerMode": lowPower, "reason": allowed ? "eligible" : "Power pilot requires unplugged, >=30% battery, nominal thermal state, Low Power Mode off"]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: documents.appendingPathComponent("q3-power-admission.json"), options: [.atomic, .completeFileProtection])
        return allowed
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value { stop(reason: "App left foreground") }
        if value { runRequestedSuite() }
    }

    /// Fixed fictional probes only; no model URL or arbitrary prompt arguments.
    private func runRequestedSuite() {
        if ["--paced-chat", "--context-boundary", "--long-chat"].contains(where: { CommandLine.arguments.contains($0) }) { runPacedChat(); return }
        guard !launchedSuite, CommandLine.arguments.contains("--evaluation-suite"), hasModel,
              let id = begin("Running the fixed fictional phone evaluation suite…") else { return }
        launchedSuite = true
        let path = modelURL.path
        let fixedPrompts = Self.prompts
        let requestedProbe = CommandLine.arguments.first(where: { $0.hasPrefix("--probe=") })
            .map { String($0.dropFirst("--probe=".count)) }
        let replayCount = CommandLine.arguments.first(where: { $0.hasPrefix("--memory-replay-count=") })
            .flatMap { Int($0.dropFirst("--memory-replay-count=".count)) }
        let mixedContexts = CommandLine.arguments.contains("--mixed-contexts")
        let reports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Qwen4Q3Reports/\(UUID().uuidString)", isDirectory: true)
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
                var plans: [(String, Int, Int, Int?)] = [
                    ("phone-2k-1", 2048, 0, nil),
                    ("phone-2k-2", 2048, 0, nil),
                    ("phone-4k-1", 4096, 0, nil),
                    ("phone-4k-2", 4096, 0, nil),
                    ("phone-fictional-facts", 2048, 1, nil),
                    ("phone-unicode", 2048, 2, nil),
                    ("phone-cancel-8", 2048, 0, 8),
                ]
                if let replayCount {
                    guard (1...20).contains(replayCount) else { throw EvaluationError.invalid("Replay count must be 1...20.") }
                    plans = (1...replayCount).map { ("memory-replay-\($0)", mixedContexts && $0 % 2 == 0 ? 4096 : 2048, 0, nil) }
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let requestedProbe, !plans.contains(where: { $0.0 == requestedProbe }) {
                    throw EvaluationError.invalid("Unknown fixed probe identifier.")
                }
                var completed: [String] = []
                for (name, context, promptIndex, cancelAt) in plans where requestedProbe == nil || name == requestedProbe {
                    if QwenGeneration.isCancellationRequested { break }
                    await MainActor.run { [weak self] in self?.status = "Running \(name)…" }
                    let progress: [String: Any] = ["probe": name, "stage": "before-hash-and-load",
                        "availableMemoryBytes": QwenGeneration.availableMemoryBytes,
                        "time": ISO8601DateFormatter().string(from: Date())]
                    try JSONSerialization.data(withJSONObject: progress, options: [.prettyPrinted, .sortedKeys])
                        .write(to: reports.appendingPathComponent(name + "-started.json"), options: [.atomic, .completeFileProtection])
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
                    "cancellationRequested": QwenGeneration.isCancellationRequested,
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

    /// Separate paced development workload; does not replace failed stress evidence.
    private func runPacedChat() {
        guard !launchedSuite, hasModel, let id = begin("Running paced fictional chat…") else { return }
        launchedSuite = true
        let boundary = CommandLine.arguments.contains("--context-boundary")
        let extended = CommandLine.arguments.contains("--long-chat")
        let powerProfile = CommandLine.arguments.contains("--power-profile")
        let total = boundary ? 2 : extended ? 8 : 6
        let prefix = boundary ? "boundary" : extended ? "long-chat" : "paced"
        let path = modelURL.path
        let reports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Qwen4Q3Reports/\(UUID().uuidString)", isDirectory: true)
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var history = [EvaluationMessage(role: "system", content: PacedChatFixture.system)]
                var completed: [String] = []
                let matchedOrder = try MatchedPowerProtocol.order(arguments: CommandLine.arguments)
                var workloadStart: TimeInterval?
                var workloadDeadline: Task<Void, Never>?
                defer { workloadDeadline?.cancel() }
                if powerProfile {
                    guard extended, !boundary else { throw EvaluationError.invalid("Power pilot requires the eight-turn suite.") }
                    try await self?.powerMarker(directory: reports, phase: "attach-wait-start")
                    await MainActor.run { [weak self] in self?.status = "Waiting for profiler confirmation; no inference will start automatically…" }
                    try await Self.waitForPowerCapture(directory: reports)
                    try await self?.powerMarker(directory: reports, phase: "capture-ready")
                    // Allow initial profiler samples and file-transfer activity to settle.
                    try await Self.powerPause(seconds: 10)
                    guard await self?.powerAdmissionAllowed() == true else {
                        throw EvaluationError.invalid("Power conditions changed before baseline; no inference started.")
                    }
                    if let matchedOrder {
                        let plan: [String: Any] = ["version": 1, "order": matchedOrder.rawValue,
                            "phaseSeconds": MatchedPowerProtocol.phaseSeconds, "turns": 8,
                            "scope": "One matched-duration pair, not a battery rating; workload padded with idle to 300 seconds"]
                        try JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys])
                            .write(to: reports.appendingPathComponent("matched-power-plan.json"), options: [.atomic, .completeFileProtection])
                        if matchedOrder == .baselineFirst { try await self?.matchedBaseline(directory: reports) }
                        try await self?.powerMarker(directory: reports, phase: "matched-workload-start")
                        workloadStart = ProcessInfo.processInfo.systemUptime
                        workloadDeadline = Task.detached { [weak self] in
                            do { try await Task.sleep(nanoseconds: UInt64(MatchedPowerProtocol.maximumWorkloadSeconds * 1e9)) }
                            catch { return }
                            guard !Task.isCancelled else { return }
                            await self?.stop(reason: "Matched power workload exceeded 300 seconds")
                        }
                    } else {
                        await MainActor.run { [weak self] in self?.status = "Power pilot: 90-second foreground idle baseline…" }
                        try await self?.powerMarker(directory: reports, phase: "baseline-before-start")
                        try await Self.powerPause(seconds: 90)
                        try await self?.powerMarker(directory: reports, phase: "workload-start")
                    }
                }
                for index in 0..<total {
                    if index > 0 {
                        await MainActor.run { [weak self] in self?.status = "Reading pause: 30 seconds before the next probe…" }
                        for _ in 0..<PacedChatFixture.pauseSeconds {
                            if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                    if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
                    if powerProfile { try await Self.checkPowerConditions() }
                    let name = "\(prefix)-\(index + 1)"
                    let request = boundary ? PacedChatFixture.boundaryBriefs[index] : extended ? PacedChatFixture.extendedChatRequests[index] : index < 4 ? PacedChatFixture.chatRequests[index] : index == 4 ? PacedChatFixture.story : PacedChatFixture.brief
                    let usesHistory = extended || (!boundary && index < 4)
                    let contextSize = boundary && index == 1 ? 4096 : 2048
                    let outputCap = boundary ? 128 : extended ? 256 : index == 4 ? 512 : index == 5 ? 128 : 256
                    var messages = usesHistory ? history : [.init(role: "system", content: PacedChatFixture.system)]
                    messages.append(.init(role: "user", content: request))
                    try encoder.encode(messages).write(to: reports.appendingPathComponent(name + "-input.json"), options: [.atomic, .completeFileProtection])
                    let progress: [String: Any] = ["probe": name, "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                        "availableMemoryBytes": QwenGeneration.availableMemoryBytes, "time": ISO8601DateFormatter().string(from: Date()),
                        "context": contextSize, "pauseSeconds": index == 0 ? 0 : PacedChatFixture.pauseSeconds]
                    try JSONSerialization.data(withJSONObject: progress, options: [.prettyPrinted, .sortedKeys])
                        .write(to: reports.appendingPathComponent(name + "-started.json"), options: [.atomic, .completeFileProtection])
                    await MainActor.run { [weak self] in self?.status = "Running \(name)…" }
                    if powerProfile { try await self?.powerMarker(directory: reports, phase: "\(name)-start") }
                    let report = try Self.performRun(path: path, prompt: request, context: contextSize,
                        output: outputCap, messages: messages) { snapshot in
                        Task { @MainActor [weak self] in
                            guard self?.operation == id else { return }
                            self?.output = snapshot
                        }
                    }
                    try encoder.encode(report).write(to: reports.appendingPathComponent(name + ".json"), options: [.atomic, .completeFileProtection])
                    if powerProfile { try await self?.powerMarker(directory: reports, phase: "\(name)-end") }
                    guard report.result.outcome == "completed", !QwenGeneration.isCancellationRequested else {
                        throw EvaluationError.invalid("Paced probe did not complete: \(name), \(report.result.outcome)")
                    }
                    completed.append(name)
                    if usesHistory { history = messages + [.init(role: "assistant", content: report.result.response)] }
                }
                if powerProfile {
                    if let matchedOrder, let workloadStart {
                        workloadDeadline?.cancel()
                        guard ProcessInfo.processInfo.systemUptime - workloadStart < MatchedPowerProtocol.maximumWorkloadSeconds else {
                            throw EvaluationError.invalid("Matched workload exceeded fixed duration; pair invalid, no retry.")
                        }
                        try await self?.powerMarker(directory: reports, phase: "matched-inference-finished")
                        await MainActor.run { [weak self] in self?.status = "Matched power: finishing the fixed 300-second workload window…" }
                        try await Self.matchedPause(start: workloadStart)
                        try await self?.powerMarker(directory: reports, phase: "matched-workload-end")
                        if matchedOrder == .workloadFirst { try await self?.matchedBaseline(directory: reports) }
                    } else {
                        try await self?.powerMarker(directory: reports, phase: "baseline-after-start")
                        await MainActor.run { [weak self] in self?.status = "Power pilot: 90-second post-workload idle baseline…" }
                        try await Self.powerPause(seconds: 90)
                        try await self?.powerMarker(directory: reports, phase: "baseline-after-end")
                    }
                }
                let terminal: [String: Any] = ["completedProbes": completed, "qualification": "paced-development-only-quality-review-required", "pauseSeconds": PacedChatFixture.pauseSeconds, "suite": prefix]
                try JSONSerialization.data(withJSONObject: terminal, options: [.prettyPrinted, .sortedKeys])
                    .write(to: reports.appendingPathComponent("suite-complete.json"), options: [.atomic, .completeFileProtection])
                await self?.finish(id: id, message: "\(prefix) suite completed: \(total) probes. Quality review pending.")
            } catch {
                let terminal = ["error": String(describing: error), "qualification": "incomplete-paced-development-evaluation"]
                try? JSONSerialization.data(withJSONObject: terminal, options: [.prettyPrinted])
                    .write(to: reports.appendingPathComponent("suite-failed.json"), options: [.atomic, .completeFileProtection])
                await self?.finish(id: id, message: "Paced suite ended: \(error)")
            }
        }
    }

    private func matchedBaseline(directory: URL) async throws {
        // Match screen content at the start of either order; never alter brightness.
        output = ""
        status = "Matched power: 300-second foreground idle baseline…"
        try powerMarker(directory: directory, phase: "matched-baseline-start")
        try await Self.matchedPause(start: ProcessInfo.processInfo.systemUptime)
        try powerMarker(directory: directory, phase: "matched-baseline-end")
    }

    nonisolated private static func matchedPause(start: TimeInterval) async throws {
        while true {
            if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
            try await checkPowerConditions()
            let remaining = try MatchedPowerProtocol.remaining(start: start, now: ProcessInfo.processInfo.systemUptime)
            if remaining == 0 { return }
            try await Task.sleep(nanoseconds: UInt64(min(1, remaining) * 1e9))
        }
    }

    private func powerMarker(directory: URL, phase: String) throws {
        let state: [String: Any] = ["phase": phase, "unixTime": Date().timeIntervalSince1970,
            "uptime": ProcessInfo.processInfo.systemUptime,
            "batteryLevel": UIDevice.current.batteryLevel, "batteryState": UIDevice.current.batteryState.rawValue,
            "brightness": UIScreen.main.brightness, "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "availableMemoryBytes": QwenGeneration.availableMemoryBytes]
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("power-\(phase).json"), options: [.atomic, .completeFileProtection])
    }

    private static func checkPowerConditions() throws {
        guard UIDevice.current.batteryState == .unplugged, UIDevice.current.batteryLevel >= 0.2,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            QwenGeneration.requestCancellation()
            throw EvaluationError.invalid("Power pilot interrupted: charging, low battery, unknown battery state, or Low Power Mode.")
        }
    }

    nonisolated private static func waitForPowerCapture(directory: URL) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let receiptURL = directory.appendingPathComponent("capture-ready.json")
        while true {
            if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
            try await checkPowerConditions()
            let decision = PowerCaptureGate.decision(
                elapsed: ProcessInfo.processInfo.systemUptime - started,
                receipt: try? Data(contentsOf: receiptURL), runID: directory.lastPathComponent)
            switch decision {
            case .ready: return
            case .expired: throw EvaluationError.invalid("Profiler confirmation timed out; no baseline or inference started.")
            case .waiting: try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    nonisolated private static func powerPause(seconds: Int) async throws {
        for _ in 0..<seconds {
            if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
            try await checkPowerConditions()
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func stop(reason: String = "Stop tapped") {
        guard busy else { return }
        if stopRequestedAt == nil { stopRequestedAt = ProcessInfo.processInfo.systemUptime; stopReason = reason }
        QwenGeneration.requestCancellation()
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
        let reportDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
        let lifecycle: [String: Any] = ["operation": id.uuidString, "message": message,
            "stopReason": stopReason ?? "none", "stopToReturnSeconds": stopToReturnSeconds ?? -1,
            "foregroundAtReturn": foreground, "time": ISO8601DateFormatter().string(from: Date())]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? JSONSerialization.data(withJSONObject: lifecycle, options: [.prettyPrinted, .sortedKeys])
            .write(to: documents.appendingPathComponent("q3-lifecycle-\(id.uuidString).json"), options: [.atomic, .completeFileProtection])
        operation = nil
        worker = nil
        busy = false
        if let priorIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = priorIdleTimerDisabled
            self.priorIdleTimerDisabled = nil
        }
        status = message
        if imported { hasModel = true }
        if let report { output = report.result.response }
        exportURL = export
    }

    nonisolated private static func performRun(path: String, prompt: String, context: Int,
                                               output: Int = 512, cancelAfterTokens: Int? = nil,
                                               messages: [EvaluationMessage]? = nil,
                                               snapshot: (String) -> Void) throws -> PhoneReport {
        try autoreleasepool {
            guard ProcessInfo.processInfo.thermalState.rawValue < 2 else {
                throw EvaluationError.invalid("Device needs to cool before the next evaluation load.")
            }
            // Candidate 2.5 GiB policy passed finite memory-trend checks only.
            // Thermal qualification and clean-build regression remain pending.
            let reserve: UInt64 = 2684354560
            guard QwenGeneration.availableMemoryBytes >= reserve else {
                throw EvaluationError.invalid("Insufficient headroom for \(reserve)-byte pre-load reserve.")
            }
            let runtime = try QwenGeneration(path: path)
            let options = try EvaluationOptions(context: context, output: output, cancelAfterTokens: cancelAfterTokens)
            let chat = messages ?? [.init(role: "system", content: PacedChatFixture.system), .init(role: "user", content: prompt)]
            let result = try runtime.generate(messages: chat, options: options, snapshot: snapshot)
            return PhoneReport(templateVersion: chat.count > 2 ? QwenGeneration.chatTemplateVersion : QwenGeneration.templateVersion,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                loadSeconds: runtime.loadSeconds, result: result)
        }
    }

    nonisolated private static func copyVerified(source: URL, destination: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == QwenGeneration.modelBytes else {
            throw EvaluationError.invalid("Choose the pinned 2,075,618,400-byte Qwen4 Q3 GGUF.")
        }
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var protectedFolder = folder
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try protectedFolder.setResourceValues(flags)
        let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard available > Int64(QwenGeneration.modelBytes) + 128 * 1024 * 1024 else {
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
            if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
            written += UInt64(chunk.count)
            guard written <= QwenGeneration.modelBytes else { throw EvaluationError.invalid("Artifact grew during import.") }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        try QwenGeneration.verifyModel(path: staged.path)
        if QwenGeneration.isCancellationRequested { throw EvaluationError.cancelled }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: destination)
        }
    }
}
