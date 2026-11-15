import Flutter
import Foundation
import UIKit
import Darwin
import SekretInference

/// No networking. The worker owns every llama object; main owns admission and
/// event delivery. Cancellation is atomic and unload acknowledges worker exit.
@available(iOS 17.0, *)
final class LocalModelPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let worker = DispatchQueue(label: "com.ricejy.sekret.local-inference", qos: .userInitiated)
    private var sink: FlutterEventSink?
    private var operation: String?
    private var runtime: LocalRuntime? // worker only
    private var loadedPath: String? // worker only
    private var observers: [NSObjectProtocol] = []
    private var unloading = false
    private var prepared = false // main only; runtime already owns its reservation

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = LocalModelPlugin()
        registrar.addMethodCallDelegate(plugin, channel: FlutterMethodChannel(
            name: "com.ricejy.sekret/local_model", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "com.ricejy.sekret/local_model_stream",
            binaryMessenger: registrar.messenger()).setStreamHandler(plugin)
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification,
                     UIApplication.didReceiveMemoryWarningNotification, ProcessInfo.thermalStateDidChangeNotification] {
            plugin.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak plugin] _ in
                if name != ProcessInfo.thermalStateDidChangeNotification || ProcessInfo.processInfo.thermalState.rawValue >= 2 {
                    plugin?.interrupt()
                }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reviewed-models", isDirectory: true)
    }

    /// Each reviewed chat model's runtime profile and where its verified
    /// weights live under `reviewed-models/`. Keep in sync with the Dart
    /// catalogue (`model_catalogue.dart`): same profile ids, caps and paths.
    private static let installed: [String: (profile: ModelProfile, path: String)] = [
        // Installed before per-model folders existed; kept so it is not downloaded again.
        ModelProfile.qwen3_4b.id: (.qwen3_4b, ModelProfile.qwen3_4b.sha256 + ".gguf"),
        ModelProfile.qwen35_4b.id: (.qwen35_4b, "qwen3.5-4b-q3km/Qwen3.5-4B-Q3_K_M.gguf"),
        ModelProfile.qwen35_2b.id: (.qwen35_2b, "qwen3.5-2b-q4km/Qwen3.5-2B-Q4_K_M.gguf"),
        ModelProfile.minicpm5_2b.id: (.minicpm5_2b, "minicpm5-2b-q4km/MiniCPM5-2B-Q4_K_M.gguf"),
        ModelProfile.minicpm5_1b.id: (.minicpm5_1b, "minicpm5-1b-q4km/MiniCPM5-1B-Q4_K_M.gguf"),
        ModelProfile.granite41_3b.id: (.granite41_3b, "granite-4.1-3b-q4km/granite-4.1-3b-Q4_K_M.gguf"),
    ]

    /// The profile named by a call, if it is reviewed and the caller's limits match.
    private static func profile(_ args: [String: Any]) -> ModelProfile? {
        guard let id = args["profile"] as? String, let entry = installed[id],
              args["context"] as? Int == entry.profile.context,
              args["output"] as? Int == entry.profile.output else { return nil }
        return entry.profile
    }

    private static var supported: Bool {
        // Initial integration is limited to the evaluated hardware. This is not
        // a promise that all 8 GB devices or all iOS versions are qualified.
        #if targetEnvironment(simulator)
        return false
        #else
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return machine == "iPhone16,2"
        #endif
    }

    /// This process's physical footprint (what Activity Monitor calls Memory).
    private static var physFootprintBytes: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : -1
    }

    /// Free memory admits a load when it covers the weights plus a margin.
    private static func ready(_ profile: ModelProfile) -> Bool {
        supported && UIApplication.shared.applicationState == .active &&
            ProcessInfo.processInfo.thermalState.rawValue < 2 &&
            LocalRuntime.availableMemoryBytes >= profile.admissionBytes
    }

    private func interrupt() {
        prepared = false
        LocalRuntime.requestCancellation()
        // Also free a model left between token preflight and generation.
        worker.async { [self] in runtime = nil; loadedPath = nil }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "diagnosticState":
            guard ProcessInfo.processInfo.arguments.contains("--sekret-model-rating-eval") else {
                result(FlutterMethodNotImplemented); return
            }
            UIDevice.current.isBatteryMonitoringEnabled = true
            result([
                "onBattery": UIDevice.current.batteryState == .unplugged,
                "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
                "applicationState": UIApplication.shared.applicationState.rawValue,
                "availableMemoryBytes": LocalRuntime.availableMemoryBytes,
                "physFootprintBytes": Self.physFootprintBytes,
                "ready": Self.ready(.qwen3_4b),
            ])
        case "supported": result(Self.supported)
        case "ready": result(Self.profile(args).map(Self.ready) ?? false)
        case "prepareStorage":
            do { result(try prepareStorage(args["directory"] as? String)) }
            catch { result(failure("storage_unavailable")) }
        case "unload":
            unloading = true
            prepared = false
            LocalRuntime.requestCancellation()
            worker.async { [self] in
                runtime = nil; loadedPath = nil
                DispatchQueue.main.async { [self] in
                    unloading = false
                    result(nil)
                }
            }
        case "cancel":
            if args["requestId"] as? String == operation {
                LocalRuntime.requestCancellation()
            }
            // Ack after any native decode has exited, not when the flag is set.
            worker.async { DispatchQueue.main.async { result(nil) } }
        case "countPrompt", "generate":
            guard let profile = Self.profile(args) else { result(failure("model_unavailable")); return }
            let canRun = Self.ready(profile) || (prepared && Self.supported &&
                UIApplication.shared.applicationState == .active &&
                ProcessInfo.processInfo.thermalState.rawValue < 2 &&
                LocalRuntime.availableMemoryBytes >= 536_870_912)
            guard operation == nil, !unloading, canRun,
                  let path = args["path"] as? String,
                  let system = args["system"] as? String,
                  let prompt = args["prompt"] as? String else {
                result(failure("model_unavailable")); return
            }
            let generating = call.method == "generate"
            let id = generating ? args["requestId"] as? String : UUID().uuidString
            guard let id, !generating || sink != nil else { result(failure("stream_failure")); return }
            operation = id
            LocalRuntime.prepareOperation() // never reset on the worker after Stop
            if generating { result(nil) }
            worker.async { [self] in
                do {
                    try validatePath(path, profile: profile)
                    if runtime == nil || loadedPath != path || runtime?.profile.id != profile.id {
                        runtime = nil; loadedPath = nil
                        guard LocalRuntime.availableMemoryBytes >= profile.admissionBytes else {
                            throw LocalModelError.invalid("model_unavailable")
                        }
                        runtime = try LocalRuntime(path: path, profile: profile)
                        loadedPath = path
                    }
                    guard !LocalRuntime.isCancellationRequested else { throw LocalModelError.cancelled }
                    let model = runtime!
                    let (_, tokens) = try model.tokenizePrompt(system: system, user: prompt)
                    guard tokens.count + profile.output <= profile.context else { throw LocalModelError.invalid("context_overflow") }
                    if generating {
                        let report = try model.generate(system: system, user: prompt,
                            options: LocalModelOptions(context: profile.context, output: profile.output)) { text in
                            DispatchQueue.main.async { [self] in
                                if operation == id { sink?(["requestId": id, "type": "snapshot", "text": text]) }
                            }
                        }
                        // A capped response is not a silently successful full answer,
                        // and leaked reasoning ("thinking-leak") is never shown as one.
                        guard report.outcome == "completed" else {
                            throw report.outcome == "cancelled" ? LocalModelError.cancelled : LocalModelError.invalid("output_limit")
                        }
                    }
                    if generating { runtime = nil; loadedPath = nil }
                    DispatchQueue.main.async { [self] in
                        guard operation == id else { return }
                        operation = nil
                        prepared = !generating && !LocalRuntime.isCancellationRequested
                        if generating { sink?(["requestId": id, "type": "completed"]) }
                        else { result(tokens.count) }
                    }
                } catch {
                    runtime = nil; loadedPath = nil
                    let code: String
                    if case LocalModelError.cancelled = error { code = "generation_interrupted" }
                    else if case LocalModelError.invalid("context_overflow") = error { code = "context_overflow" }
                    else if case LocalModelError.invalid("model_unavailable") = error { code = "model_unavailable" }
                    else { code = "stream_failure" }
                    DispatchQueue.main.async { [self] in
                        guard operation == id else { return }
                        operation = nil
                        prepared = false
                        if generating { sink?(["requestId": id, "type": "error", "code": code]) }
                        else { result(failure(code)) }
                    }
                }
            }
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func validatePath(_ path: String, profile: ModelProfile) throws {
        guard let relative = Self.installed[profile.id]?.path else { throw LocalModelError.invalid("Unreviewed model") }
        let expected = Self.modelDirectory.appendingPathComponent(relative)
        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL == expected.standardizedFileURL,
              url.resolvingSymlinksInPath() == expected.standardizedFileURL else {
            throw LocalModelError.invalid("Unowned model path")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              UInt64(values.fileSize ?? 0) == profile.bytes else {
            throw LocalModelError.invalid("Invalid model file")
        }
    }

    private func prepareStorage(_ path: String?) throws -> Int64 {
        guard let path, URL(fileURLWithPath: path).standardizedFileURL == Self.modelDirectory.standardizedFileURL else {
            throw LocalModelError.invalid("Unowned storage path")
        }
        var root = Self.modelDirectory
        guard root.resolvingSymlinksInPath() == root.standardizedFileURL else {
            throw LocalModelError.invalid("Linked storage")
        }
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try root.setResourceValues(excluded)
        // Every model folder and file, at any depth. Links are refused, not followed.
        var children: [URL] = []
        var unreadable = false
        guard let walk = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [],
            errorHandler: { _, _ in unreadable = true; return false }) else {
            throw LocalModelError.invalid("Unreadable storage")
        }
        for case let child as URL in walk { children.append(child) }
        if unreadable { throw LocalModelError.invalid("Unreadable storage") }
        for var file in [root] + children {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LocalModelError.invalid("Linked model entry") }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            try file.setResourceValues(excluded)
        }
        guard let bytes = try root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else {
            throw LocalModelError.invalid("Unknown free capacity")
        }
        return Int64(bytes)
    }

    private func failure(_ code: String) -> FlutterError {
        FlutterError(code: code, message: "Local model operation could not complete.", details: nil)
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil; interrupt(); return nil
    }
}
