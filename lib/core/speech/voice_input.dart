import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/model_catalogue.dart';
import '../models/model_library.dart';
import '../models/model_selection.dart';
import '../models/model_store.dart';
import '../platform/speech_recognizer.dart';

/// Builds the recognizer for a voice-input model. [directory] is the verified
/// model folder for downloaded models, null for Apple's.
typedef SpeechRecognizerFactory =
    SpeechRecognizer Function(CatalogueModel model, String? directory);

/// The chosen voice-input model, if any, and the one listening session.
/// A transcript only ever fills the composer; it is never sent, saved or used
/// as Knowledge Vault evidence, and the audio stays in native memory.
final class VoiceInput extends ChangeNotifier {
  VoiceInput({
    required this._choices,
    required this._selected,
    required this._recognizerFor,
    this._lease,
  }) {
    _current = _selected();
    _choices.addListener(_choiceChanged);
  }

  /// Follows the persisted voice-input choice; downloaded models are leased
  /// from their store while listening so they cannot be removed mid-session.
  factory VoiceInput.forSelection({
    required ModelSelection selection,
    required ModelLibrary library,
    required SpeechRecognizerFactory recognizerFor,
    List<CatalogueModel> catalogue = ModelCatalogue.entries,
  }) => VoiceInput(
    choices: selection,
    selected: () {
      final id = selection.selectedFor(ModelKind.voiceInput);
      return catalogue.where((model) => model.id == id).firstOrNull;
    },
    recognizerFor: recognizerFor,
    lease: (model) {
      final store = library.store(model.id);
      if (store == null) throw StateError('Model not available');
      return store.acquire();
    },
  );

  final Listenable _choices;
  final CatalogueModel? Function() _selected;
  final SpeechRecognizerFactory _recognizerFor;
  final ModelLease Function(CatalogueModel)? _lease;
  CatalogueModel? _current;
  SpeechRecognizer? _active;
  ModelLease? _held;
  bool _disposed = false;

  /// The selected voice-input model; null while voice input is off.
  CatalogueModel? get model => _current;
  bool get listening => _active != null;

  /// A recognizer for [model] that only checks or installs; listening goes
  /// through [listen]. Downloaded models need their folder, so only Apple's
  /// entry can be asked about before it is chosen.
  SpeechRecognizer probe(CatalogueModel model, {String? directory}) =>
      _recognizerFor(model, directory);

  void _choiceChanged() {
    final next = _selected();
    if (next?.id == _current?.id) return;
    // Release the lease now, so turning a model off and removing it in one
    // step never finds it still held.
    unawaited(stop());
    _current = next;
    if (!_disposed) notifyListeners();
  }

  Future<SpeechAvailability> availability() async {
    final model = _current;
    if (model == null) return const SpeechUnsupported();
    if (!model.downloadable) {
      return _recognizerFor(model, null).availability();
    }
    final ModelLease lease;
    try {
      lease = _lease!(model);
    } on Object {
      return const SpeechUnsupported();
    }
    try {
      return await _recognizerFor(model, lease.directory).availability();
    } finally {
      lease.release();
    }
  }

  /// Starts one listening session; each event is the full transcript so far.
  Stream<String> listen() {
    final model = _current;
    if (model == null || _active != null || _disposed) {
      return Stream.error(const SpeechException('busy'));
    }
    ModelLease? lease;
    try {
      if (model.downloadable) lease = _lease!(model);
    } on Object {
      return Stream.error(const SpeechException('not_installed'));
    }
    _held = lease;
    final recognizer = _recognizerFor(model, lease?.directory);
    _active = recognizer;
    notifyListeners();
    void finished() {
      if (_active != recognizer) return;
      _active = null;
      _held?.release();
      _held = null;
      if (!_disposed) notifyListeners();
    }

    final source = recognizer.listen();
    late final StreamController<String> controller;
    StreamSubscription<String>? subscription;
    controller = StreamController<String>(
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            finished();
            unawaited(controller.close());
          },
        );
      },
      onCancel: () async {
        finished();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Stops listening; the stream delivers its final transcript, then ends.
  Future<void> stop() async {
    final recognizer = _active;
    if (recognizer == null) return;
    _held?.release();
    _held = null;
    try {
      await recognizer.stop();
    } on Object {
      // Already stopped natively.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _choices.removeListener(_choiceChanged);
    unawaited(stop());
    _active = null;
    super.dispose();
  }
}
