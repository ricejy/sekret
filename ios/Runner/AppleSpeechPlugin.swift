import AVFoundation
import Flutter
import Speech
import UIKit

/// Voice input with Apple's on-device SpeechAnalyzer (iOS 26+). Audio lives in
/// memory for one session, is never written to disk, and never leaves the
/// device. Apple's speech model is fetched by iOS only from `install`, which
/// Dart calls after the person's explicit tap (ADR 0006); listening never
/// starts a download.
final class AppleSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let appleModel = "apple-speech"
  private var sink: FlutterEventSink?
  private var session: AnyObject?
  private var installing = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = AppleSpeechPlugin()
    registrar.addMethodCallDelegate(plugin, channel: FlutterMethodChannel(
      name: "com.ricejy.sekret/speech", binaryMessenger: registrar.messenger()))
    FlutterEventChannel(
      name: "com.ricejy.sekret/speech_stream", binaryMessenger: registrar.messenger()
    ).setStreamHandler(plugin)
    NotificationCenter.default.addObserver(
      plugin, selector: #selector(resignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
  }

  // Flutter delivers method calls, stream callbacks and notifications here on
  // the main thread.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    MainActor.assumeIsolated { handleOnMain(call, result: result) }
  }

  @MainActor
  private func handleOnMain(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    // Only Apple's built-in model runs here; it never takes a folder.
    let known = arguments["model"] as? String == Self.appleModel && arguments["directory"] == nil
    switch call.method {
    case "supported":
      if #available(iOS 26.0, *) { result(known) } else { result(false) }
    case "availability":
      guard known, #available(iOS 26.0, *) else { result("unsupported"); return }
      Task { @MainActor in result(await AppleSpeechSession.availability()) }
    case "install":
      guard known, #available(iOS 26.0, *) else { result(Self.error("unsupported")); return }
      guard !installing else { result(Self.error("busy")); return }
      installing = true
      Task { @MainActor in
        defer { self.installing = false }
        do {
          try await AppleSpeechSession.install()
          result(nil)
        } catch {
          result(Self.error((error as? SpeechFailure)?.code ?? "failure"))
        }
      }
    case "start":
      guard known, #available(iOS 26.0, *) else { result(Self.error("unsupported")); return }
      guard let id = arguments["requestId"] as? String, !id.isEmpty else {
        result(Self.error("failure")); return
      }
      guard session == nil, UIApplication.shared.applicationState == .active else {
        result(Self.error("busy")); return
      }
      let current = AppleSpeechSession(
        requestId: id,
        emit: { [weak self] event in self?.emit(event, from: id) })
      session = current
      result(nil)
      Task { @MainActor in await current.run() }
    case "stop":
      if #available(iOS 26.0, *), let current = session as? AppleSpeechSession,
        current.requestId == arguments["requestId"] as? String {
        current.stop()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @MainActor
  private func emit(_ event: [String: Any], from id: String) {
    var event = event
    event["requestId"] = id
    sink?(event)
    if event["type"] as? String != "transcript" { session = nil }
  }

  /// The microphone never stays open behind the app switcher or lock screen.
  @objc private func resignActive() {
    MainActor.assumeIsolated { stopSession() }
  }

  @MainActor
  private func stopSession() {
    if #available(iOS 26.0, *) { (session as? AppleSpeechSession)?.stop() }
  }

  static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events; return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    MainActor.assumeIsolated { stopSession() }
    return nil
  }
}

struct SpeechFailure: Error {
  let code: String
}

/// One listening session. The transcript is cumulative: finalized text plus
/// the current volatile guess, re-sent whole on every change.
@available(iOS 26.0, *)
@MainActor
final class AppleSpeechSession {
  let requestId: String
  private let emit: @MainActor ([String: Any]) -> Void
  private let audio = AVAudioEngine()
  private var input: AsyncStream<AnalyzerInput>.Continuation?
  private var analyzer: SpeechAnalyzer?
  private var stopping = false
  private var finalizing = false
  private var tapped = false
  private var interruption: NSObjectProtocol?

  init(requestId: String, emit: @escaping @MainActor ([String: Any]) -> Void) {
    self.requestId = requestId
    self.emit = emit
  }

  /// SpeechTranscriber where this iPhone and language support it, otherwise
  /// the DictationTranscriber fallback. Nil when neither supports the language.
  static func module() async -> (any SpeechModule)? {
    if SpeechTranscriber.isAvailable,
      let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
      return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }
    if let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) {
      return DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }
    return nil
  }

  static func availability() async -> String {
    if AVAudioApplication.shared.recordPermission == .denied { return "permissionDenied" }
    guard let module = await module() else { return "unsupported" }
    switch await AssetInventory.status(forModules: [module]) {
    case .installed: return "ready"
    case .supported, .downloading: return "needsInstall"
    default: return "unsupported"
    }
  }

  /// Asks iOS for Apple's speech model. Called only from an explicit tap.
  static func install() async throws {
    guard let module = await module(),
      let locale = (module as? any LocaleDependentSpeechModule)?.selectedLocales.first
    else { throw SpeechFailure(code: "unsupported") }
    switch await AssetInventory.status(forModules: [module]) {
    case .installed: return
    case .unsupported: throw SpeechFailure(code: "unsupported")
    default: break
    }
    _ = try? await AssetInventory.reserve(locale: locale)
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
      try await request.downloadAndInstall()
    }
  }

  func run() async {
    do {
      guard await Self.permitted() else { throw SpeechFailure(code: "permission_denied") }
      guard let module = await Self.module() else { throw SpeechFailure(code: "unsupported") }
      // Never fetch here: a missing model is reported, and Models offers it.
      guard await AssetInventory.status(forModules: [module]) == .installed else {
        throw SpeechFailure(code: "not_installed")
      }
      guard !stopping else { finish(nil); return }
      try await listen(with: module)
      finish(nil)
    } catch {
      finish((error as? SpeechFailure)?.code ?? (stopping ? nil : "failure"))
    }
  }

  func stop() {
    guard !stopping else { return }
    stopping = true
    if tapped {
      audio.inputNode.removeTap(onBus: 0)
      audio.stop()
    }
    input?.finish()
    finalize()
  }

  /// The analyzer finalizes what it heard, then its results end.
  private func finalize() {
    guard stopping, !finalizing, let analyzer else { return }
    finalizing = true
    Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
  }

  private static func permitted() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: return true
    case .denied: return false
    default: return await AVAudioApplication.requestRecordPermission()
    }
  }

  private func listen(with module: any SpeechModule) async throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setActive(true, options: [])
    defer { try? session.setActive(false, options: [.notifyOthersOnDeactivation]) }
    interruption = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: session, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.interrupted() }
    }
    defer { if let interruption { NotificationCenter.default.removeObserver(interruption) } }

    let microphone = audio.inputNode.outputFormat(forBus: 0)
    guard microphone.sampleRate > 0,
      let format = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [module], considering: microphone),
      let converter = AVAudioConverter(from: microphone, to: format)
    else { throw SpeechFailure(code: "failure") }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    input = continuation
    let analyzer = SpeechAnalyzer(modules: [module])
    self.analyzer = analyzer
    try await analyzer.start(inputSequence: stream)
    if stopping {
      continuation.finish()
      finalize()
    } else {
      audio.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone) { buffer, _ in
        // Converted in memory and handed straight to the analyzer.
        if let converted = Self.convert(buffer, with: converter, to: format) {
          continuation.yield(AnalyzerInput(buffer: converted))
        }
      }
      tapped = true
      audio.prepare()
      try audio.start()
    }

    var finalized = AttributedString()
    var volatile = AttributedString()
    func report(_ text: AttributedString, final: Bool) {
      if final {
        finalized += text
        volatile = AttributedString()
      } else {
        volatile = text
      }
      emit(["type": "transcript", "text": String((finalized + volatile).characters)])
    }
    if let transcriber = module as? SpeechTranscriber {
      for try await result in transcriber.results { report(result.text, final: result.isFinal) }
    } else if let transcriber = module as? DictationTranscriber {
      for try await result in transcriber.results { report(result.text, final: result.isFinal) }
    }
  }

  private func interrupted() {
    guard !stopping else { return }
    stop()
    emitOnce(["type": "error", "code": "interrupted"])
  }

  private var ended = false
  private func emitOnce(_ event: [String: Any]) {
    guard !ended else { return }
    ended = true
    emit(event)
  }

  private func finish(_ failure: String?) {
    stop()
    analyzer = nil
    input = nil
    emitOnce(failure.map { ["type": "error", "code": $0] } ?? ["type": "done"])
  }

  private nonisolated static func convert(
    _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    return status == .error || output.frameLength == 0 ? nil : output
  }
}
