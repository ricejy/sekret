import 'dart:async';

import 'package:flutter/services.dart';

/// Whether a voice-input model can listen right now.
sealed class SpeechAvailability {
  const SpeechAvailability();
}

final class SpeechReady extends SpeechAvailability {
  const SpeechReady();
}

/// Apple's on-device speech model is not on this iPhone yet. iOS fetches it
/// only after the person taps Download (ADR 0006).
final class SpeechNeedsInstall extends SpeechAvailability {
  const SpeechNeedsInstall();
}

/// This device, iOS version or language cannot run the model.
final class SpeechUnsupported extends SpeechAvailability {
  const SpeechUnsupported();
}

/// Microphone access was declined; only iOS Settings can grant it again.
final class SpeechPermissionDenied extends SpeechAvailability {
  const SpeechPermissionDenied();
}

final class SpeechException implements Exception {
  const SpeechException(this.code);

  /// `permission_denied`, `not_installed`, `unsupported`, `busy`,
  /// `interrupted` or `failure`.
  final String code;

  @override
  String toString() => 'SpeechException($code)';
}

/// Turns speech into text on this iPhone. Audio stays in memory for one
/// listening session: it is never saved, sent anywhere, or used as evidence.
abstract interface class SpeechRecognizer {
  /// Whether this iPhone and iOS version can ever run the model; entries
  /// that cannot are hidden (Parakeet Redux needs iOS 18).
  Future<bool> supported();

  Future<SpeechAvailability> availability();

  /// Asks iOS for Apple's speech model. Only call it from an explicit tap;
  /// downloaded models are installed by Sekret's own verified store instead.
  Future<void> install();

  /// Starts listening. Each event is the whole transcript so far; the stream
  /// ends after [stop] once the final transcript has been delivered, and
  /// fails with a [SpeechException].
  Stream<String> listen();

  /// Stops listening and discards the audio.
  Future<void> stop();
}

const speechChannel = MethodChannel('com.ricejy.sekret/speech');
const _speechEvents = EventChannel('com.ricejy.sekret/speech_stream');

/// The native speech plugin: Apple's SpeechAnalyzer, or a downloaded model
/// loaded only from its verified folder under `reviewed-models/`.
final class NativeSpeechRecognizer implements SpeechRecognizer {
  NativeSpeechRecognizer({
    required this.model,
    this.directory,
    MethodChannel? channel,
    Stream<Object?>? events,
  }) : _channel = channel ?? speechChannel,
       _events = events ?? _speechEvents.receiveBroadcastStream();

  /// Catalogue id; the native side maps it to its engine.
  final String model;

  /// The verified model folder; null for Apple's built-in model.
  final String? directory;
  final MethodChannel _channel;
  final Stream<Object?> _events;
  static int _sequence = 0;
  String? _request;

  Map<String, Object?> get _arguments => {
    'model': model,
    if (directory != null) 'directory': directory,
  };

  @override
  Future<bool> supported() async {
    try {
      return await _channel.invokeMethod<bool>('supported', {'model': model}) ==
          true;
    } on Object {
      return false;
    }
  }

  @override
  Future<SpeechAvailability> availability() async {
    try {
      return switch (await _channel.invokeMethod<String>(
        'availability',
        _arguments,
      )) {
        'ready' => const SpeechReady(),
        'needsInstall' => const SpeechNeedsInstall(),
        'permissionDenied' => const SpeechPermissionDenied(),
        _ => const SpeechUnsupported(),
      };
    } on Object {
      return const SpeechUnsupported();
    }
  }

  @override
  Future<void> install() async {
    try {
      await _channel.invokeMethod<void>('install', _arguments);
    } on PlatformException catch (error) {
      throw SpeechException(error.code);
    }
  }

  @override
  Stream<String> listen() {
    final id = 'speech-${_sequence++}';
    late StreamController<String> controller;
    StreamSubscription<Object?>? subscription;
    var ended = false;
    void end([Object? error]) {
      if (ended) return;
      ended = true;
      if (_request == id) _request = null;
      if (error != null) controller.addError(error);
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    }

    controller = StreamController<String>(
      onListen: () {
        _request = id;
        subscription = _events.listen((event) {
          if (ended || event is! Map || event['requestId'] != id) return;
          switch (event['type']) {
            case 'transcript' when event['text'] is String:
              controller.add(event['text'] as String);
            case 'done':
              end();
            case 'error':
              end(SpeechException('${event['code'] ?? 'failure'}'));
            default:
              end(const SpeechException('failure'));
          }
        }, onError: (Object _) => end(const SpeechException('failure')));
        _channel
            .invokeMethod<void>('start', {..._arguments, 'requestId': id})
            .catchError((Object error) {
              end(
                SpeechException(
                  error is PlatformException ? error.code : 'failure',
                ),
              );
            });
      },
      onCancel: () async {
        if (!ended) {
          ended = true;
          await subscription?.cancel();
          await _stop(id);
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    final id = _request;
    if (id != null) await _stop(id);
  }

  Future<void> _stop(String id) async {
    try {
      await _channel.invokeMethod<void>('stop', {'requestId': id});
    } on Object {
      // The native session is already gone.
    }
  }
}
