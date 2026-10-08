import CryptoKit
import Foundation
import FoundationModels
import ImageIO
import Network
import UIKit

/// Runs the frozen photo screening suite through Apple's on-device system model.
/// Only `SystemLanguageModel.default` is used; Private Cloud Compute is never referenced.
@MainActor
final class VisionEvaluation: ObservableObject {
    /// v1 is spent and now a development set; v2 is the held-out set for the narrowed slice.
    static let suites = [
        "v1": ("screening-v1.json", "2f396f76d91af8acac7865fc2b992425aebc50a8c6e69d64d8db3b3628e7190c"),
        "v2": ("screening-v2.json", "2e65ef96930adcd7b3ab4a78e4d1a9f8b8d04afb549edf512863fdb5c615e920"),
    ]
    static let preprocessing = "ImageIO oriented thumbnail, longest edge 1024, CGImage passed with orientation .up"

    @Published var status = "Idle"
    @Published var busy = false
    @Published var log: [String] = []
    private var task: Task<Void, Never>?
    private let path = NWPathMonitor()
    private var networkStatus = "unknown"

    init() {
        path.pathUpdateHandler = { [weak self] update in
            let value = update.status == .satisfied ? "satisfied" : "unsatisfied"
            Task { @MainActor in self?.networkStatus = value }
        }
        path.start(queue: .main)
    }

    /// `instructions` overrides the suite's system text; v2 has none of its own and requires it.
    func run(suite name: String = "v1", instructions: String? = nil) {
        guard !busy else { return }
        busy = true
        log = []
        task = Task { await runSuite(name, instructions: instructions); busy = false }
    }

    func stop() { task?.cancel() }

    private func runSuite(_ name: String, instructions: String?) async {
        let reports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VisionReports/\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            let fixtures = Bundle.main.url(forResource: "photo_screening", withExtension: nil)!
            guard let (file, expectedSHA256) = Self.suites[name] else { throw Failure("Unknown suite \(name)") }
            let suiteData = try Data(contentsOf: fixtures.appendingPathComponent(file))
            guard sha256(suiteData) == expectedSHA256 else { throw Failure("Suite differs from frozen \(file)") }
            let suite = try JSONDecoder().decode(Suite.self, from: suiteData)
            guard let system = instructions ?? (name == "v1" ? suite.system : nil) else {
                throw Failure("\(file) requires --instructions")
            }
            for item in suite.cases {
                let data = try Data(contentsOf: fixtures.appendingPathComponent(item.image))
                guard sha256(data) == item.image_sha256 else { throw Failure("Image hash mismatch: \(item.id)") }
            }
            let model = SystemLanguageModel.default
            let environment: [String: Any] = [
                "availability": String(describing: model.availability),
                "supports_vision": model.capabilities.contains(.vision),
                "context_size": model.contextSize,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "device": deviceModel(),
                "network_path_at_start": networkStatus,
                "suite": file, "suite_sha256": expectedSHA256,
                "instructions": system, "instructions_sha256": sha256(Data(system.utf8)),
                "preprocessing": Self.preprocessing,
                "sampling": "greedy", "output_cap": 128,
            ]
            try write(environment, to: reports.appendingPathComponent("environment.json"))
            append("Vision capability: \(model.capabilities.contains(.vision)); context \(model.contextSize); network \(networkStatus)")
            guard model.isAvailable else { throw Failure("System model unavailable: \(model.availability)") }
            for item in suite.cases {
                if Task.isCancelled { throw Failure("Stopped") }
                status = "Running \(item.id)"
                let result = await evaluate(item, system: system, fixtures: fixtures, model: model)
                try write(result, to: reports.appendingPathComponent("\(item.id).json"))
                append("\(item.id): \(result["response"] as? String ?? "ERROR \(result["error"] ?? "")")")
            }
            try write(["completed": suite.cases.count, "network_path_at_end": networkStatus],
                      to: reports.appendingPathComponent("suite-complete.json"))
            status = "Complete: \(reports.lastPathComponent)"
        } catch {
            try? write(["error": String(describing: error)], to: reports.appendingPathComponent("suite-failed.json"))
            status = "Failed: \(error)"
        }
    }

    /// Stage-by-stage check on the development turtle image, which is not part of the frozen suite.
    func runDiagnostic() {
        guard !busy else { return }
        busy = true
        log = []
        task = Task {
            let model = SystemLanguageModel.default
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 64)
            var stages: [String: Any] = [
                "availability": String(describing: model.availability),
                "supports_vision": model.capabilities.contains(.vision),
                "network_path": networkStatus,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
            ]
            @MainActor func stage(_ name: String, _ body: () async throws -> String) async {
                do { stages[name] = try await body() } catch { stages[name] = "ERROR \(error)" }
                append("\(name): \(stages[name]!)")
            }
            let text = "Name one primary colour."
            await stage("text_token_count") { String(try await model.tokenCount(for: Prompt { text })) }
            await stage("text_response") {
                try await LanguageModelSession(model: model).respond(to: text, options: options).content
            }
            let url = Bundle.main.url(forResource: "turtle", withExtension: "png")!
            let attachment: Attachment<ImageAttachmentContent>
            do {
                attachment = Attachment(try loadImage(url).0, orientation: .up)
            } catch {
                stages["image_load"] = "ERROR \(error)"
                busy = false
                return
            }
            let question = "Describe the animal visible in this image."
            await stage("image_response") {
                var output = ""
                for try await snapshot in LanguageModelSession(model: model).streamResponse(
                    options: options, prompt: { attachment; question }) { output = snapshot.content }
                return output
            }
            await stage("image_url_response") {
                try await LanguageModelSession(model: model).respond(options: options) {
                    Attachment(imageURL: url); question
                }.content
            }
            await stage("image_token_count") { String(try await model.tokenCount(for: Prompt { attachment; question })) }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VisionDiagnostics", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? write(stages, to: directory.appendingPathComponent("\(UUID().uuidString).json"))
            status = "Diagnostic complete"
            busy = false
        }
    }

    private func evaluate(_ item: Case, system: String, fixtures: URL, model: SystemLanguageModel) async -> [String: Any] {
        var result: [String: Any] = [
            "id": item.id, "question": item.question, "image_sha256": item.image_sha256,
            "thermal_before": ProcessInfo.processInfo.thermalState.rawValue,
            "available_memory_before": os_proc_available_memory(),
            "network_path": networkStatus,
        ]
        let started = ContinuousClock.now
        do {
            let (image, width, height) = try loadImage(fixtures.appendingPathComponent(item.image))
            result["decoded_width"] = width
            result["decoded_height"] = height
            result["preprocess_seconds"] = seconds(since: started)
            let attachment = Attachment(image, orientation: .up)
            do {
                result["prompt_token_count"] = try await model.tokenCount(for: Prompt { attachment; item.question })
            } catch {
                result["prompt_token_count_error"] = String(describing: error)
            }
            let session = LanguageModelSession(model: model, instructions: system)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 128)
            let generationStarted = ContinuousClock.now
            var firstToken: Double?
            var text = ""
            for try await snapshot in session.streamResponse(options: options, prompt: { attachment; item.question }) {
                if firstToken == nil { firstToken = seconds(since: generationStarted) }
                text = snapshot.content
            }
            result["response"] = text
            result["outcome"] = "completed"
            result["first_token_seconds"] = firstToken ?? -1
            result["generation_seconds"] = seconds(since: generationStarted)
        } catch {
            result["outcome"] = Task.isCancelled ? "cancelled" : "error"
            result["error"] = String(describing: error)
        }
        result["total_seconds"] = seconds(since: started)
        result["thermal_after"] = ProcessInfo.processInfo.thermalState.rawValue
        result["available_memory_after"] = os_proc_available_memory()
        return result
    }

    private func loadImage(_ url: URL) throws -> (CGImage, Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure("ImageIO could not read image") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure("ImageIO could not decode image")
        }
        return (image, image.width, image.height)
    }

    private func append(_ line: String) { log.append(line) }
    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    private func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

struct Suite: Decodable { let system: String; let cases: [Case] }
struct Case: Decodable { let id: String; let image: String; let image_sha256: String; let question: String }
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
