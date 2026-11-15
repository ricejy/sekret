import 'dart:async';

import '../core/platform/speech_synthesizer.dart';

/// Records what would be spoken. Each utterance stays "playing" until the
/// test calls [finish], so stop rules can be checked mid-answer. With
/// [autoFinish], every utterance completes on the next microtask.
final class FakeSpeechSynthesizer implements SpeechSynthesizer {
  FakeSpeechSynthesizer({
    this.installed = const [
      SpeechVoice(id: 'fake.voice.ada', name: 'Ada', language: 'en-GB'),
      SpeechVoice(
        id: 'fake.voice.bo',
        name: 'Bo',
        language: 'en-US',
        quality: SpeechVoiceQuality.enhanced,
      ),
    ],
    this.autoFinish = false,
  });

  final List<SpeechVoice> installed;
  final bool autoFinish;

  /// Every utterance started, with the voice it asked for.
  final spoken = <({String text, String? voice})>[];
  int stops = 0;
  Completer<void>? _current;

  bool get speaking => _current != null && !_current!.isCompleted;

  @override
  Future<List<SpeechVoice>> voices() async => installed;

  @override
  Future<void> speak(String text, {String? voice}) {
    if (_current?.isCompleted == false) _current!.complete();
    final current = _current = Completer<void>();
    spoken.add((text: text, voice: voice));
    if (autoFinish) scheduleMicrotask(finish);
    return current.future;
  }

  /// Ends the current utterance as if it had been spoken in full.
  void finish() {
    final current = _current;
    if (current != null && !current.isCompleted) current.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finish();
  }
}
