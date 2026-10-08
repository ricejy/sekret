import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../knowledge/knowledge_base.dart';
import '../platform/embedder.dart';
import '../platform/llm_backend.dart';
import '../platform/token_counter.dart';
import '../question/document_question_service.dart'
    show insufficientEvidenceMessage;
import '../storage/local_data_vault.dart';
import 'chat_workspace.dart';

final class ChatTurnResult {
  const ChatTurnResult(this.turn, {required this.earlierContextSummarized});
  final TurnRecord turn;
  final bool earlierContextSummarized;
}

/// App-lifetime generation controller for both modes. General mode never calls
/// the optional Knowledge Base. No network or shared model session is used.
/// UI integration owns one instance and routes actual backgrounding to suspend.
final class ChatEngine {
  ChatEngine({
    required this._workspace,
    required this._backend,
    required this._contextProbe,
    required ModelSnapshot model,
    this.knowledgeBase,
    this.groundedBackend,
    this.photoBackend,
    this.outputTokenReserve = 512,
  }) : _model = ModelSnapshot(
         identifier: model.identifier,
         revision: model.revision,
         metadata: Map.unmodifiable(model.metadata),
       );

  final ChatWorkspace _workspace;
  GeneralLlmBackend _backend;
  ModelContextProbe _contextProbe;
  ModelSnapshot _model;
  final KnowledgeBase? knowledgeBase;
  GroundedLlmBackend? groundedBackend;
  PhotoQuestionBackend? photoBackend;
  int outputTokenReserve;
  bool get supportsKnowledgeBase => groundedBackend != null;

  /// Only the selected model's own capability; never switches models.
  Future<bool> supportsPhotoQuestions() async {
    final backend = photoBackend;
    if (backend == null || _cleanupFailed) return false;
    try {
      return await backend.supportsPhotoQuestions();
    } on Object {
      return false;
    }
  }

  String get modelIdentifier => _model.identifier;

  /// Atomic idle-only change of backend, tokenizer and retained provenance.
  /// Existing turns keep their original model; sources are never cleared here.
  Future<void> switchModel({
    required GeneralLlmBackend backend,
    required ModelContextProbe contextProbe,
    required ModelSnapshot model,
    GroundedLlmBackend? grounded,
    PhotoQuestionBackend? photo,
    int outputTokens = 512,
    Future<void> Function()? beforeChange,
  }) async {
    if (_disposed || _cleanupFailed || isGenerating) {
      throw StateError('Finish the current response before switching models');
    }
    _changingModel = true;
    try {
      await beforeChange?.call();
      if (_disposed) throw StateError('Chat generation is disposed');
      _backend = backend;
      _contextProbe = contextProbe;
      _model = ModelSnapshot(
        identifier: model.identifier,
        revision: model.revision,
        metadata: Map.unmodifiable(model.metadata),
      );
      groundedBackend = grounded;
      photoBackend = photo;
      outputTokenReserve = outputTokens;
    } finally {
      _changingModel = false;
    }
  }

  _ActiveTurn? _active;
  bool _disposed = false;
  bool _suspended = false;
  bool _changingModel = false;
  bool _cleanupFailed = false;

  bool get isGenerating => _active != null || _changingModel;
  Future<LlmAvailability> availability() => _cleanupFailed
      ? Future.value(const ModelNotReady())
      : _backend.availability();

  /// Returns the persisted terminal turn. Streamed snapshots are observable
  /// through workspace.changes/transcript. Busy submissions are never queued.
  /// A photo turn sends only this photo and question to the model, without
  /// earlier chat context; later turns see its text answer, not the photo.
  Future<ChatTurnResult> send({
    required String chatId,
    required String text,
    Uint8List? photo,
  }) => _start(chatId, text, photo: photo);

  /// Append a new attempt using context strictly before the original turn.
  /// Neither the original answer nor subsequent turns are silently deleted.
  Future<ChatTurnResult> regenerate({
    required String chatId,
    required String turnId,
  }) => _start(chatId, '', regenerateTurnId: turnId);

  Future<ChatTurnResult> _start(
    String chatId,
    String text, {
    String? regenerateTurnId,
    Uint8List? photo,
  }) {
    if (_disposed || _suspended || _cleanupFailed || isGenerating) {
      return Future.error(
        StateError('Chat generation is not available right now.'),
      );
    }
    final active = _ActiveTurn();
    _active =
        active; // Reserve synchronously, including availability/preflight.
    return _execute(active, chatId, text, regenerateTurnId, photo).whenComplete(
      () async {
        try {
          final backend = _backend;
          if (backend is TurnLlmLifecycle) {
            await (backend as TurnLlmLifecycle).finishTurn();
          }
        } on Object {
          // Never switch/unlink a model when native shutdown is unconfirmed.
          _cleanupFailed = true;
          rethrow;
        } finally {
          _active = null;
          active.done.complete();
        }
      },
    );
  }

  Future<ChatTurnResult> _execute(
    _ActiveTurn active,
    String chatId,
    String text,
    String? regenerateTurnId,
    Uint8List? photo,
  ) async {
    // Do not race this write against cancellation: always obtain its identity
    // before recording Stop, even if Stop was tapped during admission.
    final original = regenerateTurnId == null
        ? null
        : (await _workspace.transcript(
            chatId,
          )).firstWhere((turn) => turn.id == regenerateTurnId);
    final mode =
        original?.provenance.mode ??
        (await _workspace.history())
            .firstWhere((chat) => chat.id == chatId)
            .mode;
    final grounded = mode == ChatMode.knowledgeBase;
    if (grounded && (knowledgeBase == null || groundedBackend == null)) {
      throw StateError('Knowledge Vault generation is unavailable.');
    }
    if (photo != null && (grounded || photo.isEmpty)) {
      throw StateError('Photo questions run only in General mode.');
    }
    final photoTurn = photo != null || (original?.hasPhoto ?? false);
    final question = (original?.userText ?? text).trim();
    final countDeclined = photoTurn && photoCountQuestion.hasMatch(question);
    final model = ModelSnapshot(
      identifier: _model.identifier,
      revision: _model.revision,
      metadata: {
        ..._model.metadata,
        'promptVersion': grounded
            ? groundedPromptVersion
            : photoTurn
            ? photoPromptVersion
            : generalPromptVersion,
        if (grounded) 'verificationVersion': groundedVerificationVersion,
        if (photoTurn) ...{
          'photoSha256':
              original?.provenance.model.metadata['photoSha256'] ??
              sha256.convert(photo!).toString(),
          'photoPreprocessing': photoPreprocessingVersion,
          if (countDeclined) 'declinedBy': 'count-rule',
        },
      },
    );
    var turn = grounded
        ? await _workspace.beginGroundedTurn(
            chatId: chatId,
            userText: text,
            model: model,
            regenerateTurnId: regenerateTurnId,
          )
        : await _workspace.beginGeneralTurn(
            chatId: chatId,
            userText: text,
            model: model,
            regenerateTurnId: regenerateTurnId,
            photo: photo,
          );
    var outcome = TurnOutcome.completed;
    TurnFailure? failure;
    var response = '';
    var summarized = false;
    StreamIterator<String>? iterator;
    try {
      final availability = await active.wait(_backend.availability());
      if (availability is! Available) {
        throw _TurnFailure(switch (availability) {
          DeviceNotEligible() => TurnFailure.deviceNotEligible,
          AppleIntelligenceNotEnabled() =>
            TurnFailure.appleIntelligenceNotEnabled,
          _ => TurnFailure.modelNotReady,
        });
      }
      if (photoTurn) {
        await _answerAboutPhoto(
          active,
          turn,
          question: question,
          declined: countDeclined,
          onIterator: (value) => iterator = value,
          onSnapshot: (value) => response = value,
        );
        throw const _PhotoAnswered();
      }
      var boundary = turn.ordinal;
      if (regenerateTurnId != null) {
        final turns = await active.wait(_workspace.transcript(chatId));
        boundary = turns.firstWhere((t) => t.id == regenerateTurnId).ordinal;
      }
      final context = await active.wait(
        _workspace.context(chatId, beforeOrdinal: boundary),
      );
      summarized = context.summary != null;
      final conversation = {
        'context_summary': context.summary?.text,
        'recent_turns': [
          for (final previous in context.recentTurns)
            {
              'user': previous.userText,
              'assistant': previous.assistantText,
              'outcome': previous.outcome.name,
            },
        ],
        'current_user_message': turn.userText,
      };
      final prompt = buildGeneralChatPrompt(conversation);
      final size = await active.wait(_contextProbe.contextWindowSize());
      final instructions = await active.wait(
        _contextProbe.countInstructionTokens(
          grounded ? groundedChatInstructions : generalInstructions,
        ),
      );
      String groundedPrompt(List<StoredEvidencePassage> passages) =>
          buildGroundedChatPrompt(
            conversationContext: {
              'context_summary': context.summary?.text,
              'recent_turns': conversation['recent_turns'],
            },
            question: turn.userText,
            evidence: [
              for (final passage in passages)
                (
                  sourceId: passage.knowledgeItemId,
                  sourceTitle: turn.provenance.sourceScope
                      .firstWhere(
                        (source) => source.id == passage.knowledgeItemId,
                      )
                      .title,
                  page: passage.page,
                  section: passage.heading,
                  text: passage.text,
                ),
            ],
          );
      final tokens = await active.wait(
        _contextProbe.countPromptTokens(grounded ? groundedPrompt([]) : prompt),
      );
      // A probe may count the exact system/user template as one prompt, with
      // zero separate instruction tokens. Negative counts remain invalid.
      if (size <= 0 || instructions < 0 || tokens <= 0) {
        throw const _TurnFailure(TurnFailure.streamFailure);
      }
      // Reserve the selected native output cap plus a framing safety margin.
      // Never silently truncate the current message or partial history sections.
      if (instructions + tokens + outputTokenReserve + 128 > size) {
        throw const _TurnFailure(TurnFailure.contextOverflow);
      }
      var generationPrompt = prompt;
      if (grounded) {
        // Previous user questions supply referents for follow-ups, not facts.
        // Earlier assistant responses never enter the evidence set.
        final query = [
          ...context.recentTurns
              .skip(
                context.recentTurns.length > 2
                    ? context.recentTurns.length - 2
                    : 0,
              )
              .map((prior) => prior.userText),
          turn.userText,
        ].join('\n');
        final candidates = await active.wait(
          knowledgeBase!.retrieveAcross(
            sourceIds: turn.provenance.sourceScope
                .map((source) => source.id)
                .toList(),
            question: query,
          ),
        );
        final admitted = <StoredEvidencePassage>[];
        for (final candidate in candidates) {
          final count = await active.wait(
            _contextProbe.countPromptTokens(
              groundedPrompt([...admitted, candidate]),
            ),
          );
          if (count <= 0) throw const _TurnFailure(TurnFailure.streamFailure);
          if (instructions + count + outputTokenReserve + 128 <= size) {
            admitted.add(candidate);
          }
          if (admitted.length == 4) break;
        }
        if (candidates.isNotEmpty && admitted.isEmpty) {
          throw const _TurnFailure(TurnFailure.contextOverflow);
        }
        generationPrompt = groundedPrompt(admitted);
        // Do not abandon a queued persistence operation on Stop; its one-time
        // write must settle before the terminal outcome is recorded.
        try {
          turn = await _workspace.captureEvidence(
            chatId,
            turn.id,
            admitted.map((passage) => passage.id).toList(),
          );
        } on StateError {
          throw const _TurnFailure(TurnFailure.sourcesUnavailable);
        } on VaultWriteException catch (error) {
          if (error.cause is StateError) {
            throw const _TurnFailure(TurnFailure.sourcesUnavailable);
          }
          rethrow;
        }
        active.check();
        if (admitted.isEmpty) throw const _InsufficientEvidence();
      }
      active.check();
      iterator = StreamIterator(
        grounded
            ? groundedBackend!.generateGrounded(prompt: generationPrompt)
            : _backend.generateGeneral(prompt: generationPrompt),
      );
      var lastSnapshot = '';
      while (await active.wait(iterator.moveNext())) {
        active.check();
        lastSnapshot = iterator.current;
        if (!grounded) {
          response = lastSnapshot;
          await _workspace.saveResponse(turn.id, response);
        }
      }
      active.check();
      if (lastSnapshot.trim().isEmpty) {
        throw const _TurnFailure(TurnFailure.streamFailure);
      }
      if (grounded) {
        if (lastSnapshot.trim().replaceAll("'", '’') ==
                insufficientEvidenceMessage ||
            RegExp(r'\[\s*\d+(?:\s*,\s*\d+)*\s*\]').hasMatch(lastSnapshot)) {
          throw const _InsufficientEvidence();
        }
        // Release native generation before the second, fresh-session call.
        // No grounded draft is persisted or exposed before final verification.
        await iterator.cancel();
        iterator = null;
        active.check();
        final verificationPrompt = buildGroundedVerificationPrompt(
          groundedPrompt: generationPrompt,
          draft: lastSnapshot,
        );
        final verificationInstructions = await active.wait(
          _contextProbe.countInstructionTokens(
            groundedVerificationInstructions,
          ),
        );
        final verificationTokens = await active.wait(
          _contextProbe.countPromptTokens(verificationPrompt),
        );
        if (verificationInstructions <= 0 || verificationTokens <= 0) {
          throw const _TurnFailure(TurnFailure.streamFailure);
        }
        if (verificationInstructions +
                verificationTokens +
                groundedVerificationOutputTokens +
                128 >
            size) {
          throw const _TurnFailure(TurnFailure.contextOverflow);
        }
        iterator = StreamIterator(
          groundedBackend!.verifyGrounded(prompt: verificationPrompt),
        );
        var verdict = '';
        final verificationWatch = Stopwatch()..start();
        while (await active.wait(
          iterator.moveNext().timeout(
            const Duration(seconds: 30) - verificationWatch.elapsed,
            onTimeout: () => throw const LlmException(
              LlmFailureCode.streamFailure,
              'The on-device verifier timed out.',
            ),
          ),
        )) {
          verdict = iterator.current;
        }
        active.check();
        if (parseGroundedVerification(verdict) !=
            GroundedVerificationVerdict.supported) {
          throw const _InsufficientEvidence();
        }
        response = lastSnapshot;
      }
      if (response.trim().isEmpty) {
        throw const _TurnFailure(TurnFailure.streamFailure);
      }
    } on _PhotoAnswered {
      // The photo path saved its own snapshots; record its terminal state.
    } on _InsufficientEvidence {
      outcome = TurnOutcome.insufficientEvidence;
      response = insufficientEvidenceMessage;
    } on KnowledgeScopeUnavailable {
      outcome = TurnOutcome.failed;
      failure = TurnFailure.sourcesUnavailable;
    } on EmbeddingException {
      outcome = TurnOutcome.failed;
      failure = TurnFailure.retrievalUnavailable;
    } on _TurnCancelled catch (cancelled) {
      outcome = cancelled.outcome;
    } on _TurnFailure catch (error) {
      outcome = TurnOutcome.failed;
      failure = error.failure;
    } on LlmException catch (error) {
      outcome = error.code == LlmFailureCode.interrupted
          ? TurnOutcome.interrupted
          : TurnOutcome.failed;
      failure = switch (error.code) {
        LlmFailureCode.unavailable => TurnFailure.unavailable,
        LlmFailureCode.contextOverflow => TurnFailure.contextOverflow,
        LlmFailureCode.guardrailViolation => TurnFailure.guardrailViolation,
        LlmFailureCode.streamFailure => TurnFailure.streamFailure,
        LlmFailureCode.interrupted => null,
      };
    } on Object {
      outcome = TurnOutcome.failed;
      failure = TurnFailure.streamFailure;
    } finally {
      await iterator?.cancel();
    }
    // Stop/backgrounding wins even if it arrived during the last storage write
    // or while native cancellation was being acknowledged.
    if (active.cancelled != null) {
      outcome = active.cancelled!;
      failure = null;
    }
    await _workspace.saveResponse(
      turn.id,
      response,
      outcome: outcome,
      failure: failure,
    );
    final saved = (await _workspace.transcript(
      chatId,
    )).firstWhere((t) => t.id == turn.id);
    return ChatTurnResult(saved, earlierContextSummarized: summarized);
  }

  /// No chat context, retrieval or token preflight: image token counts are
  /// unavailable natively, so context overflow is reported by the model.
  Future<void> _answerAboutPhoto(
    _ActiveTurn active,
    TurnRecord turn, {
    required String question,
    required bool declined,
    required void Function(StreamIterator<String>) onIterator,
    required void Function(String) onSnapshot,
  }) async {
    if (declined) return onSnapshot(photoCountDecline);
    final backend = photoBackend;
    if (backend == null || !await active.wait(supportsPhotoQuestions())) {
      throw const _TurnFailure(TurnFailure.photosUnsupported);
    }
    final photo = await active.wait(_workspace.turnPhoto(turn.id));
    if (photo == null) throw const _TurnFailure(TurnFailure.streamFailure);
    active.check();
    final iterator = StreamIterator(
      backend.answerAboutPhoto(photo: photo, question: question),
    );
    onIterator(iterator);
    var response = '';
    while (await active.wait(iterator.moveNext())) {
      active.check();
      response = iterator.current;
      onSnapshot(response);
      await _workspace.saveResponse(turn.id, response);
    }
    active.check();
    if (response.trim().isEmpty) {
      throw const _TurnFailure(TurnFailure.streamFailure);
    }
  }

  Future<void> stop() => _cancel(TurnOutcome.stopped);

  Future<void> _cancel(TurnOutcome outcome) async {
    final active = _active;
    if (active == null) return;
    active.cancel(outcome);
    await active.done.future;
  }

  Future<void> suspend() async {
    _suspended = true;
    await _cancel(TurnOutcome.interrupted);
    await _workspace.suspend();
  }

  Future<void> resume() async {
    if (_disposed) throw StateError('Chat generation is disposed.');
    if (isGenerating) throw StateError('Stop generation before resuming.');
    await _workspace.resume();
    _suspended = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _cancel(TurnOutcome.interrupted);
  }
}

final class _ActiveTurn {
  final done = Completer<void>();
  final signal = Completer<void>();
  TurnOutcome? cancelled;
  void cancel(TurnOutcome outcome) {
    if (cancelled != null) return;
    cancelled = outcome;
    signal.complete();
  }

  void check() {
    if (cancelled != null) throw _TurnCancelled(cancelled!);
  }

  Future<T> wait<T>(Future<T> work) async {
    // Always subscribe to work, even after cancellation, so a late platform
    // error cannot escape as an unhandled asynchronous exception.
    final value = await Future.any([
      work,
      signal.future.then<T>((_) => throw _TurnCancelled(cancelled!)),
    ]);
    check();
    return value;
  }
}

final class _TurnCancelled implements Exception {
  const _TurnCancelled(this.outcome);
  final TurnOutcome outcome;
}

final class _TurnFailure implements Exception {
  const _TurnFailure(this.failure);
  final TurnFailure failure;
}

final class _PhotoAnswered implements Exception {
  const _PhotoAnswered();
}

final class _InsufficientEvidence implements Exception {
  const _InsufficientEvidence();
}
