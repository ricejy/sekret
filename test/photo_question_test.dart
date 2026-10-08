import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sqlite3/sqlite3.dart';

import 'general_chat_engine_test.dart' show FakeGeneralModel;

final _photo = Uint8List.fromList(List.generate(64, (i) => i));

void main() {
  late LocalDataVault vault;
  late ChatWorkspace workspace;
  late FakeGeneralModel model;
  late FakePhotoModel photos;
  late ChatEngine engine;
  setUp(() async {
    vault = await openLocalDataVault(databasePath: ':memory:');
    workspace = await ChatWorkspace.open(vault);
    model = FakeGeneralModel();
    photos = FakePhotoModel();
    engine = ChatEngine(
      workspace: workspace,
      backend: model,
      contextProbe: model,
      photoBackend: photos,
      model: const ModelSnapshot(identifier: 'fake-apple', revision: '27'),
    );
  });
  tearDown(() async {
    await engine.dispose();
    await workspace.dispose();
    await vault.close();
  });

  test('photo turn sends only the photo and question and records it', () async {
    final chat = await workspace.newChat();
    await engine.send(chatId: chat.id, text: 'Earlier fictional context');
    final result = await engine.send(
      chatId: chat.id,
      text: '  What colour is the mug?  ',
      photo: _photo,
    );
    expect(result.turn.outcome, TurnOutcome.completed);
    expect(result.turn.assistantText, 'The mug is blue.');
    expect(photos.requests.single.question, 'What colour is the mug?');
    expect(photos.requests.single.photo, _photo);
    expect(model.prompts, hasLength(1));
    expect(result.turn.hasPhoto, true);
    expect(result.turn.answerLabel, 'Photo answer · model interpretation');
    expect(result.turn.provenance.model.metadata, {
      'promptVersion': photoPromptVersion,
      'photoSha256': sha256.convert(_photo).toString(),
      'photoPreprocessing': photoPreprocessingVersion,
    });
    expect(await workspace.turnPhoto(result.turn.id), _photo);

    // Follow-ups see the photo turn's text answer, never the photo itself.
    await engine.send(chatId: chat.id, text: 'Thanks');
    final context = jsonDecode(model.prompts.last) as Map<String, Object?>;
    final recent = context['recent_turns'] as List<Object?>;
    expect(recent.last, {
      'user': 'What colour is the mug?',
      'assistant': 'The mug is blue.',
      'outcome': 'completed',
    });
    expect(photos.requests, hasLength(1));
  });

  test('count questions get the fixed decline without the model', () async {
    final chat = await workspace.newChat();
    final result = await engine.send(
      chatId: chat.id,
      text: 'How many apples are in the bowl?',
      photo: _photo,
    );
    expect(result.turn.outcome, TurnOutcome.completed);
    expect(result.turn.assistantText, photoCountDecline);
    expect(result.turn.provenance.model.metadata['declinedBy'], 'count-rule');
    expect(photos.requests, isEmpty);
    for (final question in [
      'Count the chairs',
      'What is the number of windows?',
    ]) {
      expect(photoCountQuestion.hasMatch(question), true);
    }
    expect(photoCountQuestion.hasMatch('What does the counter say?'), false);
  });

  test('regeneration reuses the original photo and its hash', () async {
    final chat = await workspace.newChat();
    final first = await engine.send(
      chatId: chat.id,
      text: 'What is on the sign?',
      photo: _photo,
    );
    final again = await engine.regenerate(
      chatId: chat.id,
      turnId: first.turn.id,
    );
    expect(photos.requests.map((r) => r.photo), [_photo, _photo]);
    expect(again.turn.userText, 'What is on the sign?');
    expect(
      again.turn.provenance.model.metadata['photoSha256'],
      first.turn.provenance.model.metadata['photoSha256'],
    );
    expect(await workspace.turnPhoto(again.turn.id), _photo);
  });

  test('a text-only model fails photo turns instead of switching', () async {
    final chat = await workspace.newChat();
    final first = await engine.send(
      chatId: chat.id,
      text: 'What is on the sign?',
      photo: _photo,
    );
    await engine.switchModel(
      backend: model,
      contextProbe: model,
      model: const ModelSnapshot(identifier: 'fake-qwen', revision: '1'),
    );
    expect(await engine.supportsPhotoQuestions(), false);
    final again = await engine.regenerate(
      chatId: chat.id,
      turnId: first.turn.id,
    );
    expect(again.turn.outcome, TurnOutcome.failed);
    expect(again.turn.failure, TurnFailure.photosUnsupported);
    expect(photos.requests, hasLength(1));
  });

  test(
    'unsupported device capability fails without calling the model',
    () async {
      photos.supported = false;
      final chat = await workspace.newChat();
      final result = await engine.send(
        chatId: chat.id,
        text: 'Describe this',
        photo: _photo,
      );
      expect(result.turn.failure, TurnFailure.photosUnsupported);
      expect(photos.requests, isEmpty);
    },
  );

  test('guardrail refusals and Stop keep the photo turn readable', () async {
    final chat = await workspace.newChat();
    photos.error = const LlmException(
      LlmFailureCode.guardrailViolation,
      'Declined',
    );
    final refused = await engine.send(
      chatId: chat.id,
      text: 'Read the label',
      photo: _photo,
    );
    expect(refused.turn.outcome, TurnOutcome.failed);
    expect(refused.turn.failure, TurnFailure.guardrailViolation);

    photos.error = null;
    photos.hold();
    final pending = engine.send(
      chatId: chat.id,
      text: 'Describe the scene',
      photo: _photo,
    );
    await photos.started.future;
    photos.controller!.add('A park');
    await pumpEventQueue();
    await engine.stop();
    final stopped = await pending;
    expect(stopped.turn.outcome, TurnOutcome.stopped);
    expect(stopped.turn.assistantText, 'A park');
    expect(photos.cancelled, true);
  });

  test('photo questions are General-only', () async {
    final chat = await workspace.newChat();
    await vault.chats.updateScope(
      chatId: chat.id,
      mode: ChatMode.knowledgeBase,
      selectedSourceIds: const [],
    );
    await expectLater(
      engine.send(chatId: chat.id, text: 'Describe', photo: _photo),
      throwsStateError,
    );
    expect(photos.requests, isEmpty);
    await expectLater(
      vault.chats.appendTurn(
        chatId: chat.id,
        userText: 'x',
        assistantText: '',
        outcome: TurnOutcome.generating,
        mode: ChatMode.knowledgeBase,
        sourceScopeIds: const [],
        evidencePassageIds: const [],
        citationEvidenceIndexes: const [],
        model: const ModelSnapshot(identifier: 'm', revision: '1'),
        photo: _photo,
      ),
      throwsArgumentError,
    );
  });

  test('photos are deleted with their turn, chat and erase-all', () async {
    final chat = await workspace.newChat();
    final first = await engine.send(
      chatId: chat.id,
      text: 'Describe',
      photo: _photo,
    );
    expect((await vault.storageUsage()).chatBytes, greaterThan(_photo.length));
    await workspace.deleteFromTurn(chat.id, first.turn.id);
    expect(await workspace.turnPhoto(first.turn.id), isNull);

    final second = await engine.send(
      chatId: chat.id,
      text: 'Describe again',
      photo: _photo,
    );
    await vault.chats.stageDeletion(chat.id, DateTime.utc(2000));
    expect(await workspace.turnPhoto(second.turn.id), isNull);
    await vault.chats.reap();

    final other = await workspace.newChat();
    await engine.send(chatId: other.id, text: 'Describe', photo: _photo);
    await vault.eraseAll();
    expect((await vault.storageUsage()).chatBytes, 0);
  });

  test(
    'schema 6 gains photo storage without touching existing turns',
    () async {
      final directory = await Directory.systemTemp.createTemp('sekret-photo-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/vault.sqlite3';
      var old = await openLocalDataVault(databasePath: path);
      final chat = await old.chats.createChat();
      await old.chats.appendTurn(
        chatId: chat.id,
        userText: 'Kept',
        assistantText: 'Answer',
        outcome: TurnOutcome.completed,
        mode: ChatMode.general,
        sourceScopeIds: const [],
        evidencePassageIds: const [],
        citationEvidenceIndexes: const [],
        model: const ModelSnapshot(identifier: 'm', revision: '1'),
      );
      await old.close();
      final database = sqlite3.open(path);
      database.execute('DROP TABLE turn_photos; PRAGMA user_version = 6;');
      database.close();

      final migrated = await openLocalDataVault(databasePath: path);
      addTearDown(migrated.close);
      final turn = (await migrated.chats.listTurns(chat.id)).single;
      expect(turn.userText, 'Kept');
      expect(turn.hasPhoto, false);
      expect(await migrated.chats.turnPhoto(turn.id), isNull);
      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(
        check.select('PRAGMA user_version;').single['user_version'],
        localDataVaultSchemaVersion,
      );
    },
  );
}

final class FakePhotoModel implements PhotoQuestionBackend {
  bool supported = true;
  LlmException? error;
  final requests = <({Uint8List photo, String question})>[];
  final started = Completer<void>();
  StreamController<String>? controller;
  bool cancelled = false;

  void hold() {
    controller = StreamController<String>(onCancel: () => cancelled = true);
  }

  @override
  Future<bool> supportsPhotoQuestions() async => supported;

  @override
  Stream<String> answerAboutPhoto({
    required Uint8List photo,
    required String question,
  }) {
    requests.add((photo: photo, question: question));
    if (!started.isCompleted) started.complete();
    return controller?.stream ?? _answer();
  }

  Stream<String> _answer() async* {
    if (error != null) throw error!;
    yield 'The mug';
    yield 'The mug is blue.';
  }
}
