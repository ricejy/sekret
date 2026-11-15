import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import '../platform/speech_synthesizer.dart';

/// The person's read-aloud choice: a catalogue entry of kind `readAloud` and,
/// optionally, one of its voices. A null [model] means read aloud is off.
typedef ReadAloudChoice = ({String? model, String? voice});

/// Reads one answer aloud at a time, sentence by sentence, with the chosen
/// read-aloud model. Nothing is spoken unless the person asks, and nothing is
/// saved. It stops when asked, when the choice changes, or when disposed; the
/// chat screen also stops it on backgrounding, a new turn, or leaving the chat.
final class ReadAloud extends ChangeNotifier {
  ReadAloud({
    required Map<String, SpeechSynthesizer> synthesizers,
    required this.choice,
    this.choiceChanges,
  }) : _synthesizers = Map.unmodifiable(synthesizers) {
    choiceChanges?.addListener(_choiceChanged);
  }

  final Map<String, SpeechSynthesizer> _synthesizers;

  /// The current choice, read when reading starts and whenever it changes.
  final ReadAloudChoice Function() choice;

  /// Notifies when [choice] may have changed; reading then stops.
  final Listenable? choiceChanges;
  int _run = 0;
  String? _turnId;
  SpeechSynthesizer? _speaking;
  ReadAloudChoice? _speakingWith;
  bool _disposed = false;

  /// True when a read-aloud model is chosen and this build can speak with it.
  bool get available {
    final model = choice().model;
    return model != null && _synthesizers.containsKey(model);
  }

  /// The turn being read, or null when silent.
  String? get readingTurnId => _turnId;

  /// Voices of the chosen model; empty when read aloud is off.
  Future<List<SpeechVoice>> voices() async {
    final model = choice().model;
    final synthesizer = model == null ? null : _synthesizers[model];
    return synthesizer == null ? const [] : synthesizer.voices();
  }

  /// Reads [text] aloud for [turnId], replacing anything being read. Completes
  /// when every sentence has been spoken or reading was stopped.
  Future<void> read(String turnId, String text) async {
    await stop();
    final current = choice();
    final synthesizer = current.model == null
        ? null
        : _synthesizers[current.model];
    if (synthesizer == null) {
      throw StateError('Choose a read-aloud voice in Models first');
    }
    final sentences = readableSentences(text);
    if (sentences.isEmpty || _disposed) return;
    final run = ++_run;
    _turnId = turnId;
    _speaking = synthesizer;
    _speakingWith = current;
    notifyListeners();
    try {
      for (final sentence in sentences) {
        if (run != _run) return;
        await synthesizer.speak(sentence, voice: current.voice);
      }
    } finally {
      if (run == _run && !_disposed) {
        _turnId = null;
        _speaking = null;
        _speakingWith = null;
        notifyListeners();
      }
    }
  }

  /// Stops reading immediately; harmless when silent.
  Future<void> stop() async {
    final synthesizer = _speaking;
    if (synthesizer == null) return;
    _run++;
    _turnId = null;
    _speaking = null;
    _speakingWith = null;
    if (!_disposed) notifyListeners();
    await synthesizer.stop();
  }

  void _choiceChanged() {
    final speakingWith = _speakingWith;
    if (speakingWith != null && speakingWith != choice()) {
      stop().ignore();
    }
  }

  @override
  void dispose() {
    choiceChanges?.removeListener(_choiceChanged);
    _disposed = true;
    stop().ignore();
    super.dispose();
  }
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', //
  'blockquote', 'table', 'thead', 'tbody', 'tr', 'th', 'td', 'pre', 'hr',
};

/// The spoken form of a Markdown answer: plain sentences, in order. Markdown
/// symbols and link targets are dropped, and code blocks are skipped because
/// they do not read well aloud.
List<String> readableSentences(String markdown) {
  final blocks = <String>[];
  void visit(List<md.Node> nodes) {
    final inline = StringBuffer();
    void flush() {
      blocks.add(inline.toString());
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        if (node.tag != 'pre') visit(node.children ?? const []);
      } else {
        inline.write(node.textContent);
      }
    }
    flush();
  }

  visit(
    md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(markdown.split('\n')),
  );
  final sentence = RegExp(r'(?<=[.!?…])\s+');
  final speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);
  return [
    for (final block in blocks)
      for (final part in block.replaceAll(RegExp(r'\s+'), ' ').split(sentence))
        if (speakable.hasMatch(part)) part.trim(),
  ];
}
