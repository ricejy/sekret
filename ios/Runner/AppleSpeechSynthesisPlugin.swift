import AVFoundation
import Flutter

/// Reads answers aloud with AVSpeechSynthesizer and the voices already on the
/// iPhone. Text stays on the device and no audio is saved. Apps cannot download
/// Enhanced or Premium voices; people add them in iOS Settings.
/// Every member is used on the main thread: Flutter calls arrive there and
/// delegate callbacks hop back to it before touching state.
final class AppleSpeechSynthesisPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate,
  @unchecked Sendable {
  private let synthesizer = AVSpeechSynthesizer()
  private var pending: FlutterResult?
  private var utterance: AVSpeechUtterance?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = AppleSpeechSynthesisPlugin()
    plugin.synthesizer.delegate = plugin
    registrar.addMethodCallDelegate(plugin, channel: FlutterMethodChannel(
      name: "com.ricejy.sekret/speech_synthesis", binaryMessenger: registrar.messenger()
    ))
  }

  /// Persisted on the Dart side, so only plain identifiers are offered.
  static func validIdentifier(_ id: String) -> Bool {
    id.range(of: "^[A-Za-z0-9._-]{1,120}$", options: .regularExpression) != nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "voices":
      result(Self.installedVoices())
    case "speak":
      guard let arguments = call.arguments as? [String: Any],
        let text = arguments["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.count <= 10_000 else {
        result(FlutterError(code: "invalid_input", message: "Nothing to read.", details: nil))
        return
      }
      speak(text, voice: arguments["voice"] as? String, result: result)
    case "stop":
      cancelCurrent()
      deactivateSession()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func installedVoices() -> [[String: String]] {
    AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
      if #available(iOS 17.0, *) {
        // Novelty voices are jokes; Personal Voice needs its own permission.
        if voice.voiceTraits.contains(.isNoveltyVoice) ||
          voice.voiceTraits.contains(.isPersonalVoice) { return nil }
      }
      guard validIdentifier(voice.identifier) else { return nil }
      let quality: String
      switch voice.quality {
      case .premium: quality = "premium"
      case .enhanced: quality = "enhanced"
      default: quality = "standard"
      }
      return [
        "id": voice.identifier,
        "name": voice.name,
        "language": voice.language,
        "quality": quality,
      ]
    }
  }

  private func speak(_ text: String, voice identifier: String?, result: @escaping FlutterResult) {
    // A new utterance replaces the current one; the earlier call completes.
    cancelCurrent()
    let next = AVSpeechUtterance(string: text)
    if let identifier, Self.validIdentifier(identifier),
      let voice = AVSpeechSynthesisVoice(identifier: identifier) {
      next.voice = voice
    } else {
      next.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true)
    } catch {
      result(FlutterError(code: "audio_unavailable", message: "Audio is unavailable.", details: nil))
      return
    }
    pending = result
    utterance = next
    synthesizer.speak(next)
  }

  private func cancelCurrent() {
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    finish(nil)
  }

  private func finish(_ value: Any?) {
    let completion = pending
    pending = nil
    utterance = nil
    completion?(value)
  }

  private func release(_ spoken: AVSpeechUtterance) {
    // Callbacks for an utterance that was already replaced are ignored.
    guard spoken === utterance else { return }
    finish(nil)
    // Answers are read one sentence per call; keep the session between them
    // so other audio is not unducked and re-ducked after every sentence.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, self.pending == nil, !self.synthesizer.isSpeaking else { return }
      self.deactivateSession()
    }
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { self.release(utterance) }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { self.release(utterance) }
  }
}
