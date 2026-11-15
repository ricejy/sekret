/// How good an installed voice sounds, as the system describes it.
enum SpeechVoiceQuality { standard, enhanced, premium }

/// One voice a [SpeechSynthesizer] can speak with.
class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.name,
    required this.language,
    this.quality = SpeechVoiceQuality.standard,
  });

  /// Stable identifier passed back to [SpeechSynthesizer.speak].
  final String id;
  final String name;

  /// BCP-47 tag, for example `en-US`.
  final String language;
  final SpeechVoiceQuality quality;

  static final _validId = RegExp(r'^[A-Za-z0-9._-]{1,120}$');

  /// Voice ids are persisted, so they are restricted to a plain alphabet.
  static bool validId(String id) => _validId.hasMatch(id);
}

class SpeechSynthesisException implements Exception {
  const SpeechSynthesisException(this.message);
  final String message;
  @override
  String toString() => 'SpeechSynthesisException: $message';
}

/// Speaks text on this iPhone. Text never leaves the device and audio is never
/// saved (ADR 0006). One utterance plays at a time.
abstract interface class SpeechSynthesizer {
  /// Voices installed and usable now. Apple voices change when the person
  /// adds or removes them in iOS Settings.
  Future<List<SpeechVoice>> voices();

  /// Speaks [text] and completes when it has been spoken or [stop] was called.
  /// With a null or unknown [voice] the synthesizer's default voice is used.
  Future<void> speak(String text, {String? voice});

  /// Stops the current utterance immediately; harmless when silent.
  Future<void> stop();
}
