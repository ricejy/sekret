import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../core/chat/chat_engine.dart';
import '../core/chat/chat_workspace.dart';
import '../core/knowledge/knowledge_base.dart';
import '../core/platform/apple_embedder.dart';
import '../core/platform/apple_foundation_models.dart';
import '../core/platform/embedder.dart';
import '../core/platform/llm_backend.dart';
import '../core/question/document_question_service.dart'
    show insufficientEvidenceMessage;
import '../core/storage/local_data_vault.dart';

// Supply the committed fictional JSON through --dart-define-from-file. It is
// deliberately not a production asset or a second maintained copy of the suite.
const _suiteBase64 = String.fromEnvironment('GUARDRAIL_SUITE_BASE64');
const _sourceManifest = String.fromEnvironment(
  'EVALUATION_SOURCE_MANIFEST',
  defaultValue: '{}',
);
const _selectedIds = String.fromEnvironment('EVALUATION_CASE_IDS');
const _development = bool.fromEnvironment('EVALUATION_DEVELOPMENT');
const _runNumber = int.fromEnvironment(
  'EVALUATION_RUN_NUMBER',
  defaultValue: 1,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CupertinoApp(home: _GenerationGate()));
}

/// Observe the real native adapter; never substitute an answer or instructions.
final class _ObservedModel implements GeneralLlmBackend, GroundedLlmBackend {
  _ObservedModel(this.native);
  final AppleFoundationModels native;
  String lastOutput = '';
  String? failure;
  int generalCalls = 0;
  int groundedCalls = 0;
  int verificationCalls = 0;
  String verificationOutput = '';
  String? verificationFailure;
  Map<String, dynamic> prompt = {};

  void reset() {
    lastOutput = '';
    failure = null;
    generalCalls = 0;
    groundedCalls = 0;
    verificationCalls = 0;
    verificationOutput = '';
    verificationFailure = null;
    prompt = {};
  }

  @override
  Future<LlmAvailability> availability() => native.availability();
  @override
  Stream<String> generateGeneral({required String prompt}) {
    generalCalls++;
    this.prompt = jsonDecode(prompt) as Map<String, dynamic>;
    return _observe(native.generateGeneral(prompt: prompt));
  }

  @override
  Stream<String> generateGrounded({required String prompt}) {
    groundedCalls++;
    this.prompt = {'rawGroundedPrompt': prompt};
    return _observe(native.generateGrounded(prompt: prompt));
  }

  @override
  Stream<String> verifyGrounded({required String prompt}) async* {
    verificationCalls++;
    try {
      await for (final snapshot in native.verifyGrounded(prompt: prompt)) {
        verificationOutput = snapshot;
        yield snapshot;
      }
    } on LlmException catch (error) {
      verificationFailure = error.code.name;
      rethrow;
    }
  }

  Stream<String> _observe(Stream<String> stream) async* {
    try {
      await for (final snapshot in stream) {
        lastOutput = snapshot;
        yield snapshot;
      }
    } on LlmException catch (error) {
      failure = error.code.name;
      rethrow;
    }
  }
}

class _GenerationGate extends StatefulWidget {
  const _GenerationGate();
  @override
  State<_GenerationGate> createState() => _GenerationGateState();
}

class _GenerationGateState extends State<_GenerationGate>
    with WidgetsBindingObserver {
  String status = 'Preparing actual-model fictional evaluation…';
  bool interrupted = false;
  ChatEngine? engine;
  final results = <Map<String, Object?>>[];
  final smoke = <Map<String, Object?>>[];
  final checks = <String, bool>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      interrupted = true;
      unawaited(engine?.suspend());
    }
  }

  @override
  void dispose() {
    interrupted = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run() async {
    Directory? runDirectory;
    Directory? fixtureDirectory;
    LocalDataVault? vault;
    ChatWorkspace? workspace;
    KnowledgeBase? knowledge;
    final report = <String, Object?>{
      'schemaVersion': 1,
      'purpose': _development
          ? 'v2-engine-development-not-acceptance'
          : 'v2-engine-comparator-using-frozen-v1-fictional-cases',
      'fictional': true,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'runtime': Platform.operatingSystemVersion,
      'sourceManifest': jsonDecode(_sourceManifest),
      'generalPromptVersion': generalPromptVersion,
      'groundedPromptVersion': groundedPromptVersion,
      'verificationVersion': groundedVerificationVersion,
      'generalInstructionsSha256': sha256
          .convert(utf8.encode(generalInstructions))
          .toString(),
      'groundedInstructionsSha256': sha256
          .convert(utf8.encode(groundedChatInstructions))
          .toString(),
      'runNumber': _runNumber,
      'complete': false,
      'grading': 'pending-semantic-review',
      'results': results,
      'smoke': smoke,
      'smokeStructuralChecks': checks,
    };
    Future<void> checkpoint() async {
      if (runDirectory == null) return;
      await File('${runDirectory.path}/progress.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }

    try {
      final suiteJson = utf8.decode(base64Decode(_suiteBase64));
      final suite = jsonDecode(suiteJson) as Map<String, dynamic>;
      final excerpts = (suite['excerpts'] as List).cast<Map<String, dynamic>>();
      final cases = (suite['cases'] as List).cast<Map<String, dynamic>>();
      if (suite['fictional'] != true ||
          (_development
              ? suite['purpose'] != 'development'
              : suite['suiteID'] != 'fictional-acceptance-v1-attempt-1') ||
          cases.length != 50 ||
          excerpts.length != 20 ||
          cases.where((c) => c['answerability'] == 'answerable').length != 40 ||
          cases.map((c) => c['id']).toSet().length != 50) {
        throw StateError('Unexpected fictional fixture');
      }
      final selected = _selectedIds
          .split(',')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (!cases.map((c) => c['id']).toSet().containsAll(selected)) {
        throw StateError('Unknown rerun case');
      }
      final runCases = cases
          .where((c) => selected.isEmpty || selected.contains(c['id']))
          .toList();
      report.addAll({
        'suiteID': suite['suiteID'],
        'fixturePromptVersion': suite['promptVersion'],
        'fixtureJsonSha256': sha256.convert(utf8.encode(suiteJson)).toString(),
        'plannedCases': runCases.length,
        'scopePolicy':
            'Only fixture-provided excerpt IDs, each imported as a knowledge item; fresh chat per case.',
      });
      final documents = await getApplicationDocumentsDirectory();
      final exports = await Directory(
        '${documents.path}/v2-generation-evaluation',
      ).create(recursive: true);
      runDirectory = await exports.createTemp('run-');
      fixtureDirectory = await runDirectory.createTemp('fixture-');
      await checkpoint();
      final native = AppleFoundationModels();
      if (await native.availability() is! Available) {
        throw StateError('Model unavailable');
      }
      final embedder = AppleEmbedder();
      final embedding = await embedder.embeddingModelStatus();
      if (embedding is! EmbeddingModelAvailable) {
        throw StateError('Embedding unavailable');
      }
      report['embedding'] = {
        'implementation': embedding.implementation,
        'language': embedding.language,
        'dimensions': embedding.dimensions,
        'revision': embedding.revision,
      };
      report['contextSize'] = await native.contextWindowSize();
      final databasePath = '${fixtureDirectory.path}/fixture.sqlite';
      vault = await openLocalDataVault(databasePath: databasePath);
      workspace = await ChatWorkspace.open(vault);
      knowledge = await KnowledgeBase.open(
        vault: vault,
        embedder: embedder,
        tokenCounter: native,
      );
      final observed = _ObservedModel(native);
      ChatEngine compose() => ChatEngine(
        workspace: workspace!,
        backend: observed,
        contextProbe: native,
        groundedBackend: observed,
        knowledgeBase: knowledge,
        model: ModelSnapshot(
          identifier: 'Apple Foundation Models',
          revision: Platform.operatingSystemVersion,
        ),
      );
      engine = compose();
      final sourceIds = <String, String>{};
      final sourceKeys = <String, String>{};
      for (final excerpt in excerpts) {
        if (interrupted) throw StateError('Interrupted');
        final item = await knowledge.importText(
          title: excerpt['title'] as String,
          text: excerpt['text'] as String,
        );
        if ((await knowledge.process(item.item.id)).processingState !=
            KnowledgeProcessingState.indexed) {
          throw StateError('Index failed');
        }
        sourceIds[excerpt['id'] as String] = item.item.id;
        sourceKeys[item.item.id] = excerpt['id'] as String;
      }

      Future<(ChatTurnResult, Map<String, Object?>)> turn(
        String label,
        String chatId,
        String question, {
        String? regenerateId,
      }) async {
        if (interrupted) throw StateError('Interrupted');
        observed.reset();
        final watch = Stopwatch()..start();
        final timer = Timer(
          const Duration(seconds: 60),
          () => unawaited(engine!.stop()),
        );
        late ChatTurnResult result;
        try {
          result = await (regenerateId == null
              ? engine!.send(chatId: chatId, text: question)
              : engine!.regenerate(chatId: chatId, turnId: regenerateId));
        } finally {
          timer.cancel();
        }
        final record = result.turn;
        return (
          result,
          {
            'caseID': label,
            'question': question,
            'outcome': record.outcome.name,
            'failure': record.failure?.name,
            'output': record.assistantText,
            'nativeFinalOutput': observed.lastOutput,
            'nativeFailure': observed.failure,
            'nativeGeneralCalls': observed.generalCalls,
            'nativeGroundedCalls': observed.groundedCalls,
            'nativeVerificationCalls': observed.verificationCalls,
            'nativeVerificationOutput': observed.verificationOutput,
            'nativeVerificationFailure': observed.verificationFailure,
            'latencyMs': watch.elapsedMilliseconds,
            'exactAbstention':
                record.assistantText == insufficientEvidenceMessage,
            'earlierContextSummarized': result.earlierContextSummarized,
            'scope': record.provenance.sourceScope
                .map((s) => sourceKeys[s.id] ?? 'fictional-smoke-source')
                .toList(),
            'evidence': [
              for (final p in record.provenance.evidence)
                {
                  'source': sourceKeys[p.sourceId] ?? 'fictional-smoke-source',
                  'heading': p.heading,
                  'text': p.passageText,
                },
            ],
          },
        );
      }

      for (final item in runCases) {
        final chat = await workspace.newChat();
        await workspace.changeScope(
          chat.id,
          ChatMode.knowledgeBase,
          (item['excerptIDs'] as List).map((id) => sourceIds[id]!).toList(),
        );
        final (_, data) = await turn(
          item['id'] as String,
          chat.id,
          item['question'] as String,
        );
        results.add({
          ...data,
          'answerability': item['answerability'],
          'domain': item['domain'],
          'expectedAnswer': item['expectedAnswer'],
          'manualGrade': 'pending',
        });
        await workspace.deleteAllChats();
        await checkpoint();
        if (mounted) {
          setState(
            () => status =
                '${results.length}/${runCases.length} fictional guardrail cases recorded; not graded yet.',
          );
        }
      }
      if (selected.isEmpty) {
        final chat = await workspace.newChat();
        final prompts = [
          'For this fictional test, the project codename is Silver Otter. Reply with that codename.',
          'What project codename did I just give you?',
          'For this fictional test, our meeting day is Tuesday. Acknowledge briefly.',
          'Our fictional meeting is indoors. Acknowledge briefly.',
          'The fictional meeting starts at noon. Acknowledge briefly.',
          'What is our project codename?',
        ];
        for (var i = 0; i < prompts.length; i++) {
          final (_, data) = await turn('general-${i + 1}', chat.id, prompts[i]);
          smoke.add(data);
          await checkpoint();
        }
        checks['generalNoKnowledgeBaseEvidence'] = smoke.every(
          (r) =>
              (r['evidence'] as List).isEmpty && r['nativeGroundedCalls'] == 0,
        );
        checks['contextSummaryUsed'] =
            smoke.last['earlierContextSummarized'] == true;
        final before = (await workspace.transcript(
          chat.id,
        )).map((t) => t.assistantText).toList();
        await engine!.dispose();
        await knowledge.dispose();
        await workspace.dispose();
        await vault.close();
        vault = await openLocalDataVault(databasePath: databasePath);
        workspace = await ChatWorkspace.open(vault);
        knowledge = await KnowledgeBase.open(
          vault: vault,
          embedder: embedder,
          tokenCounter: native,
        );
        engine = compose();
        await workspace.openChat(chat.id);
        final after = (await workspace.transcript(
          chat.id,
        )).map((t) => t.assistantText).toList();
        checks['fullTranscriptSurvivesReopen'] =
            before.length == 6 && jsonEncode(before) == jsonEncode(after);
        final (_, resumed) = await turn(
          'general-resume',
          chat.id,
          'What is our project codename?',
        );
        smoke.add(resumed);
        final isolated = await workspace.newChat();
        final (_, isolation) = await turn(
          'general-isolation',
          isolated.id,
          'What project codename did I give you in another chat? If you cannot know, say so.',
        );
        smoke.add(isolation);
        checks['freshChatPromptHasNoPriorContext'] =
            observed.prompt['context_summary'] == null &&
            (observed.prompt['recent_turns'] as List).isEmpty &&
            !jsonEncode(observed.prompt).contains('Silver Otter');
        await checkpoint();

        final multi = await workspace.newChat();
        // Use two known fixture excerpts, independent of a model's output.
        final twoSources = [
          sourceIds[excerpts[0]['id']]!,
          sourceIds[excerpts[1]['id']]!,
        ];
        await workspace.changeScope(
          multi.id,
          ChatMode.knowledgeBase,
          twoSources,
        );
        final (first, multiData) = await turn(
          'multi-source',
          multi.id,
          _development
              ? 'What is the employment start date, and what is the gross monthly salary?'
              : 'What is the final day of the fixed tenancy, and how much is the security deposit?',
        );
        smoke.add(multiData);
        await workspace.changeScope(multi.id, ChatMode.knowledgeBase, [
          twoSources.last,
        ]);
        final (regenerated, regeneratedData) = await turn(
          'multi-regenerate',
          multi.id,
          first.turn.userText,
          regenerateId: first.turn.id,
        );
        smoke.add(regeneratedData);
        checks['regenerationPreservesOriginalScope'] =
            jsonEncode(
              regenerated.turn.provenance.sourceScope.map((s) => s.id).toList(),
            ) ==
            jsonEncode(twoSources);
        checks['groundedNoGeneralFallback'] = [
          ...results,
          multiData,
          regeneratedData,
        ].every((r) => r['nativeGeneralCalls'] == 0);
        await checkpoint();
      }
      if (interrupted) throw StateError('Interrupted');
      report['complete'] = true;
    } on Object {
      report['error'] = interrupted
          ? 'interrupted'
          : 'setup-or-evaluation-failure';
    } finally {
      await engine?.dispose();
      engine = null;
      await knowledge?.dispose();
      await workspace?.dispose();
      await vault?.close();
      if (fixtureDirectory != null && await fixtureDirectory.exists()) {
        await fixtureDirectory.delete(recursive: true);
      }
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      report['fixtureDatabaseRemoved'] =
          fixtureDirectory != null && !await fixtureDirectory.exists();
      await checkpoint();
      if (runDirectory != null) {
        await File('${runDirectory.path}/result.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
      }
      if (mounted) {
        setState(
          () => status = report['complete'] == true
              ? 'Fictional generation results exported. Semantic grading still pending.'
              : 'Evaluation incomplete. Partial results retained; no pass recorded.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Fictional generation gate'),
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TEST DATA — real v2 model generation. Keep this screen open.',
            ),
            const SizedBox(height: 24),
            Text(status),
          ],
        ),
      ),
    ),
  );
}
