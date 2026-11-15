import 'dart:async';

import '../core/platform/speech_recognizer.dart';

/// Deterministic voice input for tests and desktop runs: it "hears" a fixed
/// fictional sentence word by word. No microphone or audio is involved.
final class FakeSpeechRecognizer implements SpeechRecognizer {
  FakeSpeechRecognizer({
    this.state = const SpeechReady(),
    this.words = const ['Remind', 'Tuck', 'to', 'water', 'the', 'ferns'],
    this.failWith,
    this.deviceSupported = true,
  });

  bool deviceSupported;

  SpeechAvailability state;
  final List<String> words;

  /// When set, listening fails with this code after the first word.
  String? failWith;
  int installs = 0;
  int starts = 0;
  int stops = 0;
  StreamController<String>? _session;
  bool get listening => _session != null;
  int _heard = 0;

  @override
  Future<bool> supported() async => deviceSupported;

  @override
  Future<SpeechAvailability> availability() async => state;

  @override
  Future<void> install() async {
    installs++;
    if (state is SpeechNeedsInstall) state = const SpeechReady();
  }

  @override
  Stream<String> listen() {
    if (_session != null) return Stream.error(const SpeechException('busy'));
    if (state is! SpeechReady) {
      return Stream.error(
        SpeechException(
          state is SpeechPermissionDenied
              ? 'permission_denied'
              : 'not_installed',
        ),
      );
    }
    starts++;
    _heard = 0;
    final session = StreamController<String>(onCancel: () => _session = null);
    _session = session;
    return session.stream;
  }

  /// Delivers the next word as a cumulative transcript.
  void hear() {
    final session = _session;
    if (session == null || _heard >= words.length) return;
    _heard++;
    session.add(words.take(_heard).join(' '));
    if (failWith != null) {
      session.addError(SpeechException(failWith!));
      _end();
    }
  }

  @override
  Future<void> stop() async {
    if (_session == null) return;
    stops++;
    _end();
  }

  void _end() {
    final session = _session;
    _session = null;
    unawaited(session?.close());
  }
}
