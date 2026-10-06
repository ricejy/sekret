import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
