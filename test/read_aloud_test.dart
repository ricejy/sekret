import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/platform/apple_speech_synthesizer.dart';
import 'package:sekret/core/platform/speech_synthesizer.dart';
import 'package:sekret/core/speech/read_aloud.dart';
import 'package:sekret/demo/fake_speech_synthesizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('readableSentences', () {
    test('drops Markdown and code, keeps sentences in order', () {
      expect(
        readableSentences(
          '# Picnic plan\n\n'
          'Bring **fictional** sandwiches. Pack a [map](https://example.com)!\n\n'
          '- Blanket\n- Tea? Yes.\n\n'
          '```\nprint("skip me")\n```\n\n'
          '| Item | Count |\n|---|---|\n| Apples | 3 |\n\n'
          '---\n\n'
          '`ok` done…  Then rest.',
        ),
        [
          'Picnic plan',
          'Bring fictional sandwiches.',
          'Pack a map!',
          'Blanket',
          'Tea?',
          'Yes.',
          'Item',
          'Count',
          'Apples',
          '3',
          'ok done…',
          'Then rest.',
        ],
      );
    });

    test('nothing speakable reads as nothing', () {
      expect(readableSentences(''), isEmpty);
      expect(readableSentences('```\ncode\n```'), isEmpty);
      expect(readableSentences('--- \n\n * \n'), isEmpty);
    });
  });

  group('ReadAloud', () {
    late FakeSpeechSynthesizer fake;
    late ValueNotifier<ReadAloudChoice> choice;
    late ReadAloud readAloud;
    setUp(() {
      fake = FakeSpeechSynthesizer();
      choice = ValueNotifier((model: null, voice: null));
      readAloud = ReadAloud(
        synthesizers: {'voices': fake},
        choice: () => choice.value,
        choiceChanges: choice,
      );
    });
    tearDown(() {
      readAloud.dispose();
      choice.dispose();
    });

    Future<void> idle() => Future<void>.delayed(Duration.zero);

    test('is off until a read-aloud model is chosen', () async {
      expect(readAloud.available, isFalse);
      expect(await readAloud.voices(), isEmpty);
      await expectLater(readAloud.read('t1', 'Hello.'), throwsStateError);
      choice.value = (model: 'unknown', voice: null);
      expect(readAloud.available, isFalse);
      choice.value = (model: 'voices', voice: null);
      expect(readAloud.available, isTrue);
      expect(await readAloud.voices(), fake.installed);
      expect(fake.spoken, isEmpty);
    });

    test('speaks one sentence at a time with the chosen voice', () async {
      choice.value = (model: 'voices', voice: 'fake.voice.bo');
      final done = readAloud.read('t1', 'One. Two? Three!');
      await idle();
      expect(readAloud.readingTurnId, 't1');
      expect(fake.spoken.map((s) => s.text), ['One.']);
      fake.finish();
      await idle();
      expect(fake.spoken.map((s) => s.text), ['One.', 'Two?']);
      fake.finish();
      await idle();
      fake.finish();
      await done;
      expect(fake.spoken.map((s) => s.text), ['One.', 'Two?', 'Three!']);
      expect(fake.spoken.every((s) => s.voice == 'fake.voice.bo'), isTrue);
      expect(readAloud.readingTurnId, isNull);
    });

    test('stop ends reading before the next sentence', () async {
      choice.value = (model: 'voices', voice: null);
      final done = readAloud.read('t1', 'One. Two. Three.');
      await idle();
      await readAloud.stop();
      await done;
      expect(fake.spoken.map((s) => s.text), ['One.']);
      expect(fake.stops, 1);
      expect(readAloud.readingTurnId, isNull);
      await readAloud.stop();
      expect(fake.stops, 1, reason: 'stopping while silent does nothing');
    });

    test('reading another answer replaces the first', () async {
      choice.value = (model: 'voices', voice: null);
      final first = readAloud.read('t1', 'First one. First two.');
      await idle();
      final second = readAloud.read('t2', 'Second.');
      await first;
      await idle();
      expect(readAloud.readingTurnId, 't2');
      fake.finish();
      await second;
      expect(fake.spoken.map((s) => s.text), ['First one.', 'Second.']);
    });

    test('changing the read-aloud choice stops reading', () async {
      choice.value = (model: 'voices', voice: null);
      final done = readAloud.read('t1', 'One. Two.');
      await idle();
      choice.value = (model: 'voices', voice: 'fake.voice.ada');
      await done;
      expect(fake.spoken.map((s) => s.text), ['One.']);
      expect(readAloud.readingTurnId, isNull);
    });

    test('disposing stops reading', () async {
      final other = FakeSpeechSynthesizer();
      final disposable = ReadAloud(
        synthesizers: {'voices': other},
        choice: () => (model: 'voices', voice: null),
      );
      final done = disposable.read('t1', 'One. Two.');
      await idle();
      disposable.dispose();
      await done;
      expect(other.spoken, hasLength(1));
      expect(other.stops, 1);
    });
  });

  group('AppleSpeechSynthesizer', () {
    const channel = MethodChannel(AppleSpeechSynthesizer.channelName);
    final calls = <MethodCall>[];
    tearDown(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mock(Object? Function(MethodCall call) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return handler(call);
            });

    test('lists only well-formed voices', () async {
      mock(
        (_) => [
          {
            'id': 'com.apple.voice.premium.en-US.Fixture',
            'name': 'Fixture',
            'language': 'en-US',
            'quality': 'premium',
          },
          {'id': 'bad id/..', 'name': 'Bad', 'language': 'en-US'},
          {'id': 'missing.name', 'language': 'en-US'},
          'not a map',
        ],
      );
      final voices = await AppleSpeechSynthesizer().voices();
      expect(voices, hasLength(1));
      expect(voices.single.id, 'com.apple.voice.premium.en-US.Fixture');
      expect(voices.single.quality, SpeechVoiceQuality.premium);
    });

    test('speaks and stops through the channel', () async {
      mock((_) => null);
      final synthesizer = AppleSpeechSynthesizer();
      await synthesizer.speak('   ');
      expect(calls, isEmpty, reason: 'blank text is not sent');
      await synthesizer.speak('Hello.', voice: 'fixture.voice');
      await synthesizer.speak('Hi.', voice: '../bad');
      await synthesizer.stop();
      expect(calls.map((c) => c.method), ['speak', 'speak', 'stop']);
      expect(calls[0].arguments, {'text': 'Hello.', 'voice': 'fixture.voice'});
      expect(calls[1].arguments, {'text': 'Hi.'});
    });

    test('a failure is reported without platform details', () async {
      mock((_) => throw PlatformException(code: 'audio_unavailable'));
      await expectLater(
        AppleSpeechSynthesizer().speak('Hello.'),
        throwsA(isA<SpeechSynthesisException>()),
      );
      await AppleSpeechSynthesizer().stop();
    });

    test('without the plugin there are no voices', () async {
      expect(await AppleSpeechSynthesizer().voices(), isEmpty);
    });
  });
}
