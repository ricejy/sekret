// Historical grounding replay, deliberately outside the portable test/ suite.
// Replays fictional native responses through the real ChatEngine admission and
// post-generation admission. The verifier verdict is now a controlled double;
// these tests do not prove native model or verifier quality.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/chat/chat_engine.dart';
import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/knowledge/knowledge_base.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sekret/demo/fake_native_capabilities.dart';

import '../../test/grounded_chat_engine_test.dart'
    show GroundedModel, QueryEmbedder;

void main() {
  const minimize = bool.fromEnvironment('MINIMIZE');
  final report =
      jsonDecode(
            File(
              'eval/guardrails/v2-prompt-v3-development-repeat-2026-09-13.json',
            ).readAsStringSync(),
          )
          as Map;
  final suite =
      jsonDecode(
            File('eval/guardrails/development_suite.json').readAsStringSync(),
          )
          as Map;
  for (final (id, expected) in [
    ('LEG-A09', TurnOutcome.completed),
    ('LEG-U03', TurnOutcome.insufficientEvidence),
  ]) {
    test(
      '$id captured native answer receives the semantically correct outcome',
      () async {
        final row = (report['results'] as List).cast<Map>().singleWhere(
          (r) => r['caseID'] == id,
        );
        final passages = minimize
            ? <Map>[
                {
                  'source': 'legal-05-confidentiality',
                  'heading': '',
                  'text': id == 'LEG-A09'
                      ? "Nothing in this clause prevents discussion of Elena's own pay."
                      : 'Elena may report suspected wrongdoing to a regulator.',
                },
              ]
            : (row['evidence'] as List).cast<Map>();
        final sourceKey = passages.first['source'];
        final excerpt = (suite['excerpts'] as List).cast<Map>().singleWhere(
          (e) => e['id'] == sourceKey,
        );
        final vault = await openLocalDataVault(databasePath: ':memory:');
        final workspace = await ChatWorkspace.open(vault);
        final model = GroundedModel()
          ..verdict = id == 'LEG-U03' ? 'NOT_ESTABLISHED' : 'SUPPORTED'
          ..answer = minimize && id == 'LEG-U03'
              ? 'Elena reported suspected wrongdoing to a regulator.'
              : row['nativeFinalOutput'] as String;
        final knowledge = await KnowledgeBase.open(
          vault: vault,
          embedder: QueryEmbedder(),
          tokenCounter: const FakeTokenCounter(),
        );
        final engine = ChatEngine(
          workspace: workspace,
          backend: model,
          groundedBackend: model,
          contextProbe: model,
          knowledgeBase: knowledge,
          model: const ModelSnapshot(
            identifier: 'fictional-native-replay',
            revision: '1',
          ),
        );
        try {
          final item = await vault.knowledge.beginProcessing(
            title: excerpt['title'] as String,
            sourceType: KnowledgeSourceType.pastedText,
            sourceBytes: Uint8List(0),
            fingerprint: id,
          );
          await vault.knowledge.completeIndex(
            knowledgeItemId: item.id,
            extractedText: passages.map((p) => p['text']).join('\n'),
            passages: [
              for (var i = 0; i < passages.length; i++)
                EvidencePassageDraft(
                  ordinal: i,
                  text: passages[i]['text'] as String,
                  heading: passages[i]['heading'] as String,
                  page: null,
                  tokenCount: 20,
                  vector: Uint8List.fromList([127, 0]),
                  vectorScale: 1 / 127,
                ),
            ],
          );
          final chat = await workspace.newChat();
          await workspace.changeScope(chat.id, ChatMode.knowledgeBase, [
            item.id,
          ]);
          final result = await engine.send(
            chatId: chat.id,
            text: row['question'] as String,
          );
          expect(result.turn.provenance.evidence, hasLength(passages.length));
          expect(model.prompts, hasLength(1));
          expect(model.generalCalls, 0);
          expect(
            result.turn.outcome,
            expected,
            reason:
                'Admission must follow the completed verifier judgment, not lexical overlap.',
          );
        } finally {
          await engine.dispose();
          await knowledge.dispose();
          await workspace.dispose();
          await vault.close();
        }
      },
    );
  }
}
