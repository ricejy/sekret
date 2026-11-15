import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/models/model_catalogue.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/platform/local_model_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native smoke fixture uses the exact app instructions and JSON framing',
    () {
      final fixture =
          jsonDecode(
                File(
                  'native/SekretInference/Tests/SekretInferenceTests/Fixtures/general-chat.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(fixture['system'], localGeneralInstructions);
      expect(localGeneralInstructions, generalInstructions);
      expect(
        fixture['prompt'],
        buildGeneralChatPrompt({
          'context_summary': null,
          'recent_turns': [],
          'current_user_message': 'Reply exactly: Copper Finch.',
        }),
      );
    },
  );
  const channel = MethodChannel('test-local-model');
  final calls = <MethodCall>[];
  late StreamController<Object?> events;
  late LocalModelBackend backend;
  setUp(() {
    calls.clear();
    events = StreamController<Object?>.broadcast();
    backend = LocalModelBackend(
      profile: ModelCatalogue.qwen.profile!,
      path: '/app/models/verified.gguf',
      channel: channel,
      events: events.stream,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'ready' => true,
            'countPrompt' => 123,
            _ => null,
          };
        });
  });
  tearDown(() async {
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'counts the full native template exactly once, with fixed bounds',
    () async {
      expect(await backend.contextWindowSize(), 2048);
      expect(await backend.countInstructionTokens(generalInstructions), 0);
      expect(calls, isEmpty);
      expect(
        await backend.countPromptTokens('{"current_user_message":"Hello"}'),
        123,
      );
      expect(calls.single.arguments, {
        'profile': 'qwen3-4b-instruct-2507',
        'context': 2048,
        'output': 256,
        'path': '/app/models/verified.gguf',
        'system': localGeneralInstructions,
        'prompt': '{"current_user_message":"Hello"}',
      });
      await expectLater(
        backend.countInstructionTokens('grounded prompt'),
        throwsStateError,
      );
      expect(backend, isNot(isA<GroundedLlmBackend>()));
    },
  );
  test(
    'streams matching snapshots, rejects stale events, acknowledges cancellation',
    () async {
      final snapshots = <String>[];
      final sub = backend
          .generateGeneral(prompt: 'fixture')
          .listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      final id = (calls.single.arguments as Map)['requestId'];
      events.add({'requestId': 'stale', 'type': 'snapshot', 'text': 'wrong'});
      events.add({'requestId': id, 'type': 'snapshot', 'text': 'Hello'});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(snapshots, ['Hello']);
      expect(calls.last.method, 'cancel');
      expect(calls.last.arguments, {'requestId': id});
      await backend.finishTurn();
      expect(calls.last.method, 'unload');
    },
  );
  test('each profile names itself and its own limits to native', () async {
    for (final model in ModelCatalogue.entries) {
      final profile = model.profile;
      if (profile == null) continue;
      calls.clear();
      final local = LocalModelBackend(
        profile: profile,
        path: '/app/models/${model.id}.gguf',
        channel: channel,
        events: events.stream,
      );
      expect(await local.contextWindowSize(), profile.context);
      expect(await local.availability(), isA<Available>());
      await local.countPromptTokens('fixture');
      final sub = local.generateGeneral(prompt: 'fixture').listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), [
        'ready',
        'countPrompt',
        'generate',
      ]);
      for (final call in calls) {
        expect(call.arguments, containsPair('profile', profile.id));
        expect(call.arguments, containsPair('context', profile.context));
        expect(call.arguments, containsPair('output', profile.outputCap));
      }
      await sub.cancel();
    }
  });
  test('native error is typed and does not expose native details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'countPrompt') {
            throw PlatformException(
              code: 'context_overflow',
              message: 'private payload',
            );
          }
          return null;
        });
    await expectLater(
      backend.countPromptTokens('fixture'),
      throwsA(
        isA<LlmException>()
            .having((e) => e.code, 'code', LlmFailureCode.contextOverflow)
            .having((e) => e.message, 'message', isNot(contains('private'))),
      ),
    );
  });
}
