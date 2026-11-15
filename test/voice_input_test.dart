import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/knowledge/knowledge_base.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/models/model_library.dart';
import 'package:sekret/core/models/model_store.dart';
import 'package:sekret/core/platform/speech_recognizer.dart';
import 'package:sekret/core/speech/voice_input.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sekret/demo/fake_native_capabilities.dart';
import 'package:sekret/demo/fake_speech_recognizer.dart';
import 'package:sekret/ui/chat/chat_screen.dart';
import 'package:sekret/ui/models/models_screen.dart';
import 'package:sekret/ui/sekret_brand.dart';

import 'chat_screen_test.dart' show UiModel;
import 'model_library_test.dart' show PathTransport, voiceFixture;
import 'model_store_test.dart' show Policy;

/// A voice-input choice that tests flip directly.
class Choice extends ChangeNotifier {
  CatalogueModel? _model;
  CatalogueModel? get model => _model;
  set model(CatalogueModel? value) {
    _model = value;
    notifyListeners();
  }
}

class _Lease {
  int held = 0;
}

void main() {
  test('Apple speech is an opt-in entry iOS manages', () {
    const apple = ModelCatalogue.appleSpeech;
    expect(apple.kind, ModelKind.voiceInput);
    expect(apple.runtime, ModelRuntime.apple);
    expect(apple.downloadable, isFalse);
    expect(apple.artifacts, isEmpty);
    expect(apple.isNew, isTrue);
    expect(ModelCatalogue.byId(apple.id), same(apple));
    // Only Apple speech is offered until a downloaded runtime lands.
    expect(
      ModelCatalogue.entries.where(
        (model) => model.kind == ModelKind.voiceInput,
      ),
      [apple],
    );
  });

  group('VoiceInput', () {
    late Choice choice;
    late FakeSpeechRecognizer recognizer;
    late _Lease lease;
    final directories = <String?>[];
    late VoiceInput voice;
    late Directory root;
    late ModelStore store;

    setUp(() async {
      choice = Choice();
      recognizer = FakeSpeechRecognizer();
      lease = _Lease();
      directories.clear();
      root = await Directory.systemTemp.createTemp('sekret-voice-');
      store = ModelStore(
        directory: root,
        policy: Policy(),
        transport: PathTransport(),
        model: voiceFixture,
      );
      await store.initialize();
      await store.install();
      voice = VoiceInput(
        choices: choice,
        selected: () => choice.model,
        recognizerFor: (model, directory) {
          directories.add(directory);
          return recognizer;
        },
        lease: (model) {
          lease.held++;
          return store.acquire();
        },
      );
    });
    tearDown(() async {
      voice.dispose();
      await store.close();
      await root.delete(recursive: true);
    });

    test('off until chosen, and refuses to listen while off', () async {
      expect(voice.model, isNull);
      expect(await voice.availability(), isA<SpeechUnsupported>());
      await expectLater(voice.listen(), emitsError(isA<SpeechException>()));
      choice.model = ModelCatalogue.appleSpeech;
      expect(voice.model, ModelCatalogue.appleSpeech);
      expect(await voice.availability(), isA<SpeechReady>());
      expect(directories.last, isNull);
    });

    test(
      'a downloaded model is leased from its folder while listening',
      () async {
        choice.model = voiceFixture;
        final transcripts = <String>[];
        final done = Completer<void>();
        voice.listen().listen(transcripts.add, onDone: done.complete);
        expect(voice.listening, isTrue);
        expect(directories.last, store.modelDirectory.path);
        // Removal is refused while the model is listening.
        await expectLater(store.remove(), throwsStateError);
        recognizer.hear();
        recognizer.hear();
        await voice.stop();
        await done.future;
        expect(transcripts, ['Remind', 'Remind Tuck']);
        expect(voice.listening, isFalse);
        expect(recognizer.stops, 1);
        await store.remove();
      },
    );

    test(
      'turning voice input off stops listening and frees the model',
      () async {
        choice.model = voiceFixture;
        final done = Completer<void>();
        voice.listen().listen((_) {}, onDone: done.complete);
        choice.model = null;
        // The lease is released synchronously, so removal can follow at once.
        await store.remove();
        await done.future;
        expect(recognizer.stops, 1);
        expect(voice.listening, isFalse);
      },
    );
  });

  group('composer', () {
    late LocalDataVault vault;
    late ChatWorkspace workspace;
    late KnowledgeBase knowledge;
    late ChatEngine engine;
    late UiModel model;
    late Choice choice;
    late FakeSpeechRecognizer recognizer;
    late VoiceInput voice;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      await tester.pumpAndSettle();
    }

    Finder field() => find.byWidgetPredicate(
      (widget) =>
          widget is CupertinoTextField && widget.placeholder == 'Message',
    );
    String text(WidgetTester tester) =>
        tester.widget<CupertinoTextField>(field()).controller!.text;
    CupertinoButton button(WidgetTester tester, String label) =>
        tester.widget<CupertinoButton>(
          find.ancestor(
            of: find.bySemanticsLabel(label),
            matching: find.byType(CupertinoButton),
          ),
        );

    void voiceTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        vault = await openLocalDataVault(databasePath: ':memory:');
        workspace = await ChatWorkspace.open(vault);
        knowledge = await KnowledgeBase.open(
          vault: vault,
          embedder: const FakeEmbedder(),
          tokenCounter: const FakeTokenCounter(),
        );
        model = UiModel();
        engine = ChatEngine(
          workspace: workspace,
          backend: model,
          contextProbe: model,
          groundedBackend: model,
          photoBackend: model,
          knowledgeBase: knowledge,
          model: const ModelSnapshot(identifier: 'fake', revision: '1'),
        );
        choice = Choice();
        recognizer = FakeSpeechRecognizer();
        voice = VoiceInput(
          choices: choice,
          selected: () => choice.model,
          recognizerFor: (_, _) => recognizer,
        );
        await tester.pumpWidget(
          CupertinoApp(
            localizationsDelegates: const [
              DefaultMaterialLocalizations.delegate,
            ],
            home: ChatScreen(
              workspace: workspace,
              engine: engine,
              knowledge: knowledge,
              voiceInput: voice,
              onKnowledgeBase: () {},
              onPreview: (_) async {},
              onLink: (_) async {},
            ),
          ),
        );
        await settle(tester);
        try {
          await body(tester);
        } finally {
          final stopping = engine.stop();
          await settle(tester);
          await stopping;
          await tester.pumpWidget(const SizedBox.shrink());
          voice.dispose();
          await engine.dispose();
          await knowledge.dispose();
          await workspace.dispose();
          await vault.close();
        }
      });
    }

    voiceTest('the mic appears only while a voice-input model is chosen', (
      tester,
    ) async {
      expect(find.bySemanticsLabel('Voice input'), findsNothing);
      choice.model = ModelCatalogue.appleSpeech;
      await settle(tester);
      expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
      choice.model = null;
      await settle(tester);
      expect(find.bySemanticsLabel('Voice input'), findsNothing);
    });

    voiceTest(
      'a transcript fills the field after typed text and is never sent',
      (tester) async {
        choice.model = ModelCatalogue.appleSpeech;
        await settle(tester);
        await tester.enterText(field(), 'Note:');
        await settle(tester);
        await tester.tap(find.bySemanticsLabel('Voice input'));
        await settle(tester);
        expect(recognizer.starts, 1);
        expect(find.textContaining('Nothing is sent'), findsOneWidget);
        // Send waits until listening stops, so the final words are seen first.
        expect(button(tester, 'Send').onPressed, isNull);
        recognizer.hear();
        recognizer.hear();
        await settle(tester);
        expect(text(tester), 'Note: Remind Tuck');
        await tester.tap(find.bySemanticsLabel('Stop voice input'));
        await settle(tester);
        expect(recognizer.stops, 1);
        expect(text(tester), 'Note: Remind Tuck');
        expect(find.textContaining('Nothing is sent'), findsNothing);
        final chat = workspace.currentChatId!;
        expect(await workspace.transcript(chat), isEmpty);
        expect(button(tester, 'Send').onPressed, isNotNull);
      },
    );

    voiceTest('listening stops when the app leaves the foreground', (
      tester,
    ) async {
      choice.model = ModelCatalogue.appleSpeech;
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Voice input'));
      await settle(tester);
      recognizer.hear();
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(recognizer.stops, 1);
      expect(recognizer.listening, isFalse);
      expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(text(tester), 'Remind');
    });

    voiceTest('the mic is disabled while a response is generating', (
      tester,
    ) async {
      choice.model = ModelCatalogue.appleSpeech;
      model.stream = StreamController<String>();
      await settle(tester);
      await tester.enterText(field(), 'Fictional question');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump();
      expect(button(tester, 'Voice input').onPressed, isNull);
      model.stream!.add('Fictional answer.');
      await model.stream!.close();
      await settle(tester);
      expect(button(tester, 'Voice input').onPressed, isNotNull);
    });

    voiceTest('a missing speech model or microphone access is explained', (
      tester,
    ) async {
      choice.model = ModelCatalogue.appleSpeech;
      recognizer.state = const SpeechNeedsInstall();
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Voice input'));
      await settle(tester);
      expect(recognizer.starts, 0);
      expect(recognizer.installs, 0, reason: 'never downloads without a tap');
      expect(find.textContaining('speech model in Models'), findsOneWidget);
      recognizer.state = const SpeechPermissionDenied();
      await tester.tap(find.bySemanticsLabel('Voice input'));
      await settle(tester);
      expect(find.textContaining('microphone access'), findsOneWidget);
    });

    voiceTest('a failed session keeps the words heard and reports it', (
      tester,
    ) async {
      choice.model = ModelCatalogue.appleSpeech;
      recognizer.failWith = 'interrupted';
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Voice input'));
      await settle(tester);
      recognizer.hear();
      await settle(tester);
      expect(text(tester), 'Remind');
      expect(find.textContaining('another app used the microphone'), findsOne);
      expect(find.bySemanticsLabel('Voice input'), findsOneWidget);
    });
  });

  group('Models screen', () {
    testWidgets('hides models this iPhone cannot run; Apple downloads on tap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final apple = FakeSpeechRecognizer(state: const SpeechNeedsInstall());
      final unsupported = FakeSpeechRecognizer(deviceSupported: false);
      final choice = Choice();
      final voice = VoiceInput(
        choices: choice,
        selected: () => choice.model,
        recognizerFor: (model, _) =>
            model.id == ModelCatalogue.appleSpeech.id ? apple : unsupported,
      );
      final directory = Directory('/fixture/reviewed-models');
      final library = ModelLibrary(
        directory: directory,
        stores: [
          ModelStore(
            directory: directory,
            policy: Policy(),
            transport: PathTransport(),
            model: voiceFixture,
          ),
        ],
      );
      await tester.pumpWidget(
        CupertinoApp(
          theme: SekretBrand.theme,
          home: ModelsScreen(
            model: const FakeLlmBackend(),
            openSystemSettings: () async {},
            library: library,
            voiceInput: voice,
            supportsLocalModel: () async => true,
            catalogue: [
              ModelCatalogue.apple,
              ModelCatalogue.appleSpeech,
              voiceFixture,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice input'));
      await tester.pumpAndSettle();
      expect(find.text('Apple Speech'), findsOneWidget);
      expect(find.text('Fixture Voice'), findsNothing);
      expect(
        find.text('Built into iOS · Speech model not downloaded'),
        findsOneWidget,
      );

      await tester.tap(find.text('Download speech model'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Apple sees your IP address'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(apple.installs, 0);

      await tester.tap(find.text('Download speech model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(apple.installs, 1);
      expect(
        find.text('Built into iOS · Tap the circle to use'),
        findsOneWidget,
      );
      expect(find.text('Download speech model'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      voice.dispose();
      await library.close();
    });
  });
}
