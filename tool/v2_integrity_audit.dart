import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sekret/core/chat/chat_workspace.dart';
import 'package:sekret/core/knowledge/knowledge_base.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sekret/demo/fake_native_capabilities.dart';
import 'package:sqlite3/sqlite3.dart';

const _contentTables = [
  'chats',
  'turns',
  'turn_provenance',
  'turn_source_scope',
  'turn_evidence',
  'turn_citations',
  'context_summaries',
  'chat_selected_sources',
  'knowledge_items',
  'knowledge_pages',
  'knowledge_passages',
  'processing_checkpoints',
  'knowledge_passages_fts',
];

void _require(bool condition, String check) {
  if (!condition) throw StateError('Integrity check failed: $check');
}

Map<String, Object> _audit(
  String path,
  String stage,
  Map<String, int> expected,
) {
  final db = sqlite3.open(path);
  try {
    _require(
      db.select('PRAGMA integrity_check;').single.values.single == 'ok',
      '$stage SQLite',
    );
    _require(
      db.select('PRAGMA foreign_key_check;').isEmpty,
      '$stage foreign keys',
    );
    db.execute(
      "INSERT INTO knowledge_passages_fts(knowledge_passages_fts) VALUES ('integrity-check');",
    );
    final counts = {
      for (final table in _contentTables)
        table:
            db.select('SELECT COUNT(*) AS n FROM $table;').single['n'] as int,
    };
    final mismatches =
        db.select('''
      SELECT COUNT(*) AS n FROM knowledge_passages_fts f
      LEFT JOIN knowledge_passages p ON p.id = f.passage_id
      WHERE p.id IS NULL OR p.knowledge_item_id != f.knowledge_item_id
         OR p.heading != f.heading OR p.text != f.text;
    ''').single['n']
            as int;
    final duplicateFtsIds = db.select('''
      SELECT passage_id FROM knowledge_passages_fts
      GROUP BY passage_id HAVING COUNT(*) != 1;
    ''').length;
    _require(
      mismatches == 0 &&
          duplicateFtsIds == 0 &&
          counts['knowledge_passages'] == counts['knowledge_passages_fts'],
      '$stage FTS membership',
    );
    for (final entry in expected.entries) {
      _require(counts[entry.key] == entry.value, '$stage ${entry.key} count');
    }
    return {
      'stage': stage,
      'sqliteIntegrity': 'ok',
      'foreignKeyViolations': 0,
      'ftsMismatches': 0,
      'counts': counts,
    };
  } finally {
    db.close();
  }
}

/// Non-UI audit. Creates and removes only its own unique fictional fixture folder.
/// Never accepts a path to an existing vault and never exports content or IDs.
Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'sekret-v2-integrity-',
  );
  final path = '${directory.path}/fictional.sqlite3';
  var now = DateTime.utc(2026, 1, 1);
  final vault = await openLocalDataVault(databasePath: path, clock: () => now);
  final workspace = await ChatWorkspace.open(vault, clock: () => now);
  final knowledge = await KnowledgeBase.open(
    vault: vault,
    embedder: const FakeEmbedder(),
    tokenCounter: const FakeTokenCounter(),
  );
  final results = <Map<String, Object>>[];
  var sequence = 0;
  Future<({String chat, String source, String firstTurn})> seed() async {
    final item = await knowledge.importText(
      title: 'Fictional audit source',
      text:
          'RETURN POLICY\nFictional record ${sequence++}: return the camera equipment within seven days.',
    );
    await knowledge.process(item.item.id);
    final passages = await vault.knowledge.listIndexedEvidence(item.item.id);
    _require(passages.isNotEmpty, 'fixture indexed');
    final chat = await workspace.newChat();
    await workspace.changeScope(chat.id, ChatMode.knowledgeBase, [
      item.item.id,
    ]);
    final turn = await vault.chats.appendTurn(
      chatId: chat.id,
      userText: 'When is the fictional equipment returned?',
      assistantText: 'Within seven days.',
      outcome: TurnOutcome.completed,
      mode: ChatMode.knowledgeBase,
      sourceScopeIds: [item.item.id],
      evidencePassageIds: [passages.first.id],
      citationEvidenceIndexes: [0],
      model: const ModelSnapshot(identifier: 'fictional-audit', revision: '1'),
    );
    await vault.chats.saveContextSummary(
      chatId: chat.id,
      summarizedThroughOrdinal: turn.ordinal,
      text: 'Fictional equipment return.',
    );
    return (chat: chat.id, source: item.item.id, firstTurn: turn.id);
  }

  try {
    results.add(
      _audit(path, 'fresh_schema', {for (final t in _contentTables) t: 0}),
    );
    var fixture = await seed();
    results.add(
      _audit(path, 'populated', {
        'chats': 1,
        'turns': 1,
        'context_summaries': 1,
        'turn_evidence': 1,
      }),
    );
    final pending = await vault.knowledge.beginProcessing(
      title: 'Fictional pending source',
      sourceType: KnowledgeSourceType.photo,
      sourceBytes: Uint8List.fromList([1, 2]),
      fingerprint: 'fictional-pending',
    );
    await vault.knowledge.saveCheckpoint(
      knowledgeItemId: pending.id,
      stage: 'ocr',
      completedUnits: 0,
      totalUnits: 1,
      artifact: Uint8List.fromList([3]),
    );
    await knowledge.cancelImport(pending.id);
    results.add(
      _audit(path, 'cancel_import', {
        'knowledge_items': 1,
        'processing_checkpoints': 0,
      }),
    );
    await knowledge.delete(fixture.source);
    _require(
      (await workspace.transcript(
        fixture.chat,
      )).single.provenance.evidence.single.sourceDeleted,
      'source deletion retains marked citation',
    );
    results.add(
      _audit(path, 'delete_source', {
        'knowledge_items': 0,
        'knowledge_pages': 0,
        'knowledge_passages': 0,
        'chat_selected_sources': 0,
        'turn_evidence': 1,
        'turn_citations': 1,
      }),
    );
    await workspace.deleteFromTurn(fixture.chat, fixture.firstTurn);
    results.add(
      _audit(path, 'delete_turn_tail', {
        'turns': 0,
        'turn_provenance': 0,
        'turn_evidence': 0,
        'turn_citations': 0,
        'context_summaries': 0,
      }),
    );
    await workspace.deleteChat(fixture.chat);
    now = now.add(const Duration(seconds: 6));
    await workspace.resume();
    results.add(_audit(path, 'finalize_chat_deletion', {'chats': 0}));
    fixture = await seed();
    now = now.add(const Duration(days: 31));
    final preview = await workspace.previewRetention(
      RetentionPolicy.thirtyDays,
    );
    await workspace.confirmRetention(preview);
    results.add(
      _audit(path, 'retention_reap', {
        'chats': 0,
        'turns': 0,
        'turn_evidence': 0,
        'context_summaries': 0,
        'knowledge_items': 1,
      }),
    );
    await seed();
    await workspace.deleteAllChats();
    results.add(
      _audit(path, 'delete_all_chats', {
        'chats': 0,
        'turns': 0,
        'turn_source_scope': 0,
        'turn_evidence': 0,
        'knowledge_items': 2,
      }),
    );
    await knowledge.suspend();
    for (final item in await vault.knowledge.list()) {
      await knowledge.delete(item.id);
    }
    results.add(
      _audit(path, 'delete_entire_knowledge_base', {
        for (final t in _contentTables) t: 0,
      }),
    );
    await knowledge.resume();
    await seed();
    await knowledge.suspend();
    await workspace.suspend();
    await vault.eraseAll();
    results.add(
      _audit(path, 'erase_all', {for (final t in _contentTables) t: 0}),
    );
  } finally {
    await knowledge.dispose();
    await workspace.dispose();
    await vault.close();
    // This folder was created by this invocation and contains only its fixtures.
    await directory.delete(recursive: true);
  }
  stdout.writeln(
    jsonEncode({
      'schemaVersion': 1,
      'passed': true,
      'fixtureOnly': true,
      'vaultSchema': localDataVaultSchemaVersion,
      'checks': results,
    }),
  );
}
