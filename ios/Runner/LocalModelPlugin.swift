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
    private var runtime: QwenRuntime? // worker only
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

    private static var ready: Bool {
        supported && UIApplication.shared.applicationState == .active &&
            ProcessInfo.processInfo.thermalState.rawValue < 2 &&
            QwenRuntime.availableMemoryBytes >= 2_684_354_560
    }

    private func interrupt() {
        prepared = false
        QwenRuntime.requestCancellation()
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
                "availableMemoryBytes": QwenRuntime.availableMemoryBytes,
                "ready": Self.ready,
            ])
        case "supported": result(Self.supported)
        case "ready": result(Self.ready)
        case "prepareStorage":
            do { result(try prepareStorage(args["directory"] as? String)) }
            catch { result(failure("storage_unavailable")) }
        case "unload":
            unloading = true
            prepared = false
            QwenRuntime.requestCancellation()
            worker.async { [self] in
                runtime = nil; loadedPath = nil
                DispatchQueue.main.async { [self] in
                    unloading = false
                    result(nil)
                }
            }
        case "cancel":
            if args["requestId"] as? String == operation {
                QwenRuntime.requestCancellation()
            }
            // Ack after any native decode has exited, not when the flag is set.
            worker.async { DispatchQueue.main.async { result(nil) } }
        case "countPrompt", "generate":
            let canRun = Self.ready || (prepared && Self.supported &&
                UIApplication.shared.applicationState == .active &&
                ProcessInfo.processInfo.thermalState.rawValue < 2 &&
                QwenRuntime.availableMemoryBytes >= 536_870_912)
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
            QwenRuntime.prepareOperation() // never reset on the worker after Stop
            if generating { result(nil) }
            worker.async { [self] in
                do {
                    try validatePath(path)
                    if runtime == nil || loadedPath != path {
                        runtime = nil; loadedPath = nil
                        guard QwenRuntime.availableMemoryBytes >= 2_684_354_560 else {
                            throw LocalModelError.invalid("model_unavailable")
                        }
                        runtime = try QwenRuntime(path: path)
                        loadedPath = path
                    }
                    guard !QwenRuntime.isCancellationRequested else { throw LocalModelError.cancelled }
                    let model = runtime!
                    let (_, tokens) = try model.tokenizePrompt(system: system, user: prompt)
                    guard tokens.count + 256 <= 2048 else { throw LocalModelError.invalid("context_overflow") }
                    if generating {
                        let report = try model.generate(system: system, user: prompt,
                            options: LocalModelOptions(context: 2048, output: 256)) { text in
                            DispatchQueue.main.async { [self] in
                                if operation == id { sink?(["requestId": id, "type": "snapshot", "text": text]) }
                            }
                        }
                        // A capped response is not a silently successful full answer.
                        guard report.outcome == "completed" else {
                            throw report.outcome == "cancelled" ? LocalModelError.cancelled : LocalModelError.invalid("output_limit")
                        }
                    }
                    if generating { runtime = nil; loadedPath = nil }
                    DispatchQueue.main.async { [self] in
                        guard operation == id else { return }
                        operation = nil
                        prepared = !generating && !QwenRuntime.isCancellationRequested
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

    private func validatePath(_ path: String) throws {
        let expected = Self.modelDirectory.appendingPathComponent(QwenRuntime.modelSHA256 + ".gguf")
        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL == expected.standardizedFileURL,
              url.resolvingSymlinksInPath() == expected.standardizedFileURL else {
            throw LocalModelError.invalid("Unowned model path")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              UInt64(values.fileSize ?? 0) == QwenRuntime.modelBytes else {
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
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
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
