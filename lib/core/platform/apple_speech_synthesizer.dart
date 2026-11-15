import 'package:flutter/services.dart';

import 'speech_synthesizer.dart';

/// AVSpeechSynthesizer voices installed on this iPhone. Sekret cannot download
/// Enhanced or Premium voices; people add them in iOS Settings.
final class AppleSpeechSynthesizer implements SpeechSynthesizer {
  AppleSpeechSynthesizer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.ricejy.sekret/speech_synthesis';
  final MethodChannel _channel;

  @override
  Future<List<SpeechVoice>> voices() async {
    try {
      final payload = await _channel.invokeListMethod<Object?>('voices');
      return [for (final entry in payload ?? const <Object?>[]) ?_voice(entry)];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      throw const SpeechSynthesisException('Could not list voices.');
    }
  }

  static SpeechVoice? _voice(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name'];
    final language = entry['language'];
    if (id is! String ||
        !SpeechVoice.validId(id) ||
        name is! String ||
        language is! String) {
      return null;
    }
    return SpeechVoice(
      id: id,
      name: name,
      language: language,
      quality: switch (entry['quality']) {
        'premium' => SpeechVoiceQuality.premium,
        'enhanced' => SpeechVoiceQuality.enhanced,
        _ => SpeechVoiceQuality.standard,
      },
    );
  }

  @override
  Future<void> speak(String text, {String? voice}) async {
    if (text.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': text,
        if (voice != null && SpeechVoice.validId(voice)) 'voice': voice,
      });
    } on MissingPluginException {
      throw const SpeechSynthesisException('Read aloud is unavailable.');
    } on PlatformException {
      throw const SpeechSynthesisException('Could not read this aloud.');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Nothing can be playing without the plugin.
    } on PlatformException {
      // Stopping is best effort; the next speak replaces any utterance.
    }
  }
}
