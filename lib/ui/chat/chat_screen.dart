import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../sekret_brand.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import '../../core/chat/chat_engine.dart';
import '../../core/chat/chat_workspace.dart';
import '../../core/models/model_catalogue.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../core/platform/llm_backend.dart';
import '../../core/storage/local_data_vault.dart';
import 'answer_content.dart';
import 'chat_sheets.dart';
import '../accessible_controls.dart';

/// UI only: the app owns the workspace, knowledge module, engine and lifecycle.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.workspace,
    required this.engine,
    required this.knowledge,
    required this.onKnowledgeBase,
    required this.onPreview,
    required this.onLink,
    this.onSettings,
    this.onImportSource,
    this.onPickPhoto,
    this.modelRevision,
  });
  final ChatWorkspace workspace;
  final ChatEngine engine;
  final String? modelRevision;
  final KnowledgeBase knowledge;
  final VoidCallback onKnowledgeBase;
  final Future<void> Function(KnowledgePreview) onPreview;
  final Future<void> Function(Uri) onLink;
  final Future<void> Function()? onSettings;

  /// The app owns pickers and imports into the existing Knowledge Base.
  final Future<KnowledgeImportResult?> Function(
    BuildContext context,
    KnowledgeSourceType type,
  )?
  onImportSource;

  /// Picks one photo for a question in this chat; it is not imported into
  /// the Knowledge Base. Null when cancelled.
  final Future<Uint8List?> Function()? onPickPhoto;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _messageFocus = FocusNode();
  final _scroll = ScrollController();
  final _drafts = <String, String>{};
  final _expandedSources = <String>{};
  final _subscriptions = <StreamSubscription<void>>[];
  ChatRecord? _chat;
  List<TurnRecord> _turns = [];
  List<KnowledgeItemRecord> _items = [];
  LlmAvailability? _availability;
  String? _error;
  bool _summary = false;
  bool _submitting = false;
  bool _importing = false;
  bool _changingSources = false;
  bool _choosingSources = false;
  bool _photosSupported = false;
  Uint8List? _photo;
  final _turnPhotos = <String, Future<Uint8List?>>{};
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(widget.workspace.changes.listen((_) => _load()));
    _subscriptions.add(
      widget.knowledge.changes.listen(
        (_) => _load(),
        onError: (Object _) => _load(),
      ),
    );
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelRevision != widget.modelRevision ||
        oldWidget.engine != widget.engine) {
      _availability = null;
      _checkAvailability();
    }
  }

  @override
  void didChangeMetrics() {
    if (!_scroll.hasClients || _scroll.position.extentAfter < 100) _toBottom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAvailability();
  }

  Future<void> _initialize() async {
    try {
      if (widget.workspace.currentChatId == null) {
        await widget.workspace.newChat();
      }
      await _load();
      await _checkAvailability();
    } on Object {
      _report('Could not open this chat. Try again.');
    }
  }

  Future<void> _checkAvailability() async {
    final model = widget.engine.modelIdentifier;
    try {
      final value = await widget.engine.availability();
      final photos = await widget.engine.supportsPhotoQuestions();
      if (mounted && widget.engine.modelIdentifier == model) {
        setState(() {
          _availability = value;
          _photosSupported = photos;
        });
      }
    } on Object {
      _report('Could not check the on-device model. Try again.');
    }
  }

  void _report(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _load() async {
    final revision = ++_revision;
    try {
      final chats = await widget.workspace.history();
      final id = widget.workspace.currentChatId;
      final chat = chats.where((c) => c.id == id).firstOrNull;
      final turns = chat == null
          ? <TurnRecord>[]
          : await widget.workspace.transcript(chat.id);
      final items = await widget.knowledge.catalogue();
      final summary =
          chat != null && await widget.workspace.hasContextSummary(chat.id);
      if (!mounted || revision != _revision) return;
      final switched = _chat?.id != chat?.id;
      final nearBottom =
          !_scroll.hasClients || _scroll.position.extentAfter < 100;
      setState(() {
        if (switched) {
          _photo = null;
          if (_chat != null) _drafts[_chat!.id] = _input.text;
          _input.text = _drafts[chat?.id] ?? '';
        }
        _chat = chat;
        _turns = turns;
        _items = items.map((i) => i.item).toList();
        _summary = summary;
      });
      if (switched || nearBottom) _toBottom();
    } on Object {
      if (revision == _revision) _report('Could not refresh this chat.');
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  bool get _busy => _submitting || widget.engine.isGenerating;

  /// A Knowledge Base chat whose sources were all deleted stays grounded;
  /// Send explains instead of falling back to model knowledge.
  bool get _sourcesReady =>
      _chat?.mode != ChatMode.knowledgeBase ||
      _chat!.selectedSourceIds.isEmpty ||
      (_chat!.selectedSourceIds.every(
        (id) => _items.any(
          (item) =>
              item.id == id &&
              item.processingState == KnowledgeProcessingState.indexed,
        ),
      ));

  Future<void> _send({TurnRecord? regenerate}) async {
    final chat = _chat;
    if (chat == null ||
        _busy ||
        _changingSources ||
        _importing ||
        _choosingSources) {
      return;
    }
    final text = _input.text.trim();
    final photo = regenerate == null ? _photo : null;
    if (regenerate == null &&
        (text.isEmpty ||
            !_sourcesReady ||
            _availability is! Available ||
            (photo != null && !_photoReady))) {
      return;
    }
    final grounded = regenerate == null
        ? chat.mode == ChatMode.knowledgeBase &&
              chat.selectedSourceIds.isNotEmpty
        : regenerate.provenance.mode == ChatMode.knowledgeBase;
    if (regenerate == null &&
        chat.mode == ChatMode.knowledgeBase &&
        chat.selectedSourceIds.isEmpty) {
      _report(
        'The sources for this chat were deleted. Add sources with the paperclip or start a new chat.',
      );
      return;
    }
    if (grounded && !widget.engine.supportsKnowledgeBase) {
      _report('This model does not support Knowledge Base answers.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    if (regenerate == null) {
      _input.clear();
      _photo = null;
      _drafts.remove(chat.id);
    }
    _toBottom();
    try {
      if (regenerate == null) {
        await widget.engine.send(chatId: chat.id, text: text, photo: photo);
      } else {
        await widget.engine.regenerate(chatId: chat.id, turnId: regenerate.id);
      }
    } on Object {
      if (regenerate == null) {
        _drafts[chat.id] = text;
        if (mounted && _chat?.id == chat.id && _input.text.isEmpty) {
          _input.text = text;
          _photo ??= photo;
        }
      }
      _report(
        'Could not start this turn. Check the original sources and model, then retry.',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        await _load();
      }
    }
  }

  Future<void> _newChat() async {
    try {
      await widget.workspace.newChat();
      await _load();
    } on Object {
      _report('Could not start a new chat.');
    }
  }

  Future<void> _scope(String chatId, List<String> ids) async {
    if (_busy || _changingSources || _importing) return;
    setState(() => _changingSources = true);
    try {
      await widget.workspace.changeScope(
        chatId,
        ids.isEmpty ? ChatMode.general : ChatMode.knowledgeBase,
        ids,
      );
      await _load();
    } on Object {
      _report('Could not change selected sources.');
    } finally {
      if (mounted) setState(() => _changingSources = false);
    }
  }

  Future<void> _chooseSources(ChatRecord chat) async {
    setState(() => _choosingSources = true);
    try {
      final selected = await Navigator.of(context).push<List<String>>(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (_) => SourceSelection(
            knowledge: widget.knowledge,
            selected: chat.mode == ChatMode.knowledgeBase
                ? chat.selectedSourceIds
                : const [],
          ),
        ),
      );
      if (selected != null && mounted) {
        final latest = (await widget.workspace.history())
            .where((candidate) => candidate.id == chat.id)
            .firstOrNull;
        if (!mounted) return;
        if (latest == null ||
            latest.mode != chat.mode ||
            latest.selectedSourceIds.length != chat.selectedSourceIds.length ||
            !latest.selectedSourceIds.toSet().containsAll(
              chat.selectedSourceIds,
            )) {
          _report('Selected sources changed. Open the source chooser again.');
          return;
        }
        await _scope(chat.id, selected);
      }
    } on Object {
      _report('Could not choose sources. Try again.');
    } finally {
      if (mounted) setState(() => _choosingSources = false);
    }
  }

  Future<void> _addSource() async {
    final chat = _chat;
    if (chat == null ||
        _busy ||
        _importing ||
        _changingSources ||
        _choosingSources) {
      return;
    }
    setState(() => _choosingSources = true);
    _messageFocus.unfocus();
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        // Photos attach to the message; PDFs are imported into the Knowledge
        // Base. Photo and text imports remain available in Knowledge.
        actions: [
          if (widget.onPickPhoto != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'askPhoto'),
              child: const Text('Photo Library'),
            ),
          if (widget.onImportSource != null)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(context, KnowledgeSourceType.pdf.name),
              child: const Text('Import PDF'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'existing'),
            child: const Text('Choose from Knowledge Base'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (mounted) setState(() => _choosingSources = false);
    if (!mounted || action == null) return;
    if (action == 'existing') {
      await _chooseSources(chat);
      return;
    }
    if (action == 'askPhoto') {
      await _pickPhoto(chat);
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.onImportSource!(
        context,
        KnowledgeSourceType.values.byName(action),
      );
      if (result == null) return;
      if (result.duplicate) {
        if (!mounted) return;
        final useExisting = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Already in your Knowledge Base'),
            content: Text(
              'Use “${result.item.title}” in this chat? No second copy was added.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use existing source'),
              ),
            ],
          ),
        );
        if (useExisting != true) return;
      }
      // Capture the initiating chat, not whichever chat is visible after a
      // native picker returns. The workspace merges with its latest scope.
      await widget.workspace.addSource(chat.id, result.item.id);
      if (mounted) await _load();
    } on Object {
      _report(
        'Could not add this source to the chat. Check your Knowledge Base and try again.',
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Photo questions are General turns on a model with image input only.
  bool get _photoReady => _photoBlocker == null;

  String? get _photoBlocker => !_photosSupported
      ? 'This model does not support images.'
      : _chat?.mode == ChatMode.knowledgeBase &&
            _chat!.selectedSourceIds.isNotEmpty
      ? 'Remove the selected sources to ask about a photo.'
      : null;

  Future<void> _pickPhoto(ChatRecord chat) async {
    final blocker = _photoBlocker;
    if (blocker != null) {
      _report(blocker);
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final photo = await widget.onPickPhoto!();
      if (photo != null &&
          photo.isNotEmpty &&
          mounted &&
          _chat?.id == chat.id) {
        setState(() => _photo = photo);
        _messageFocus.requestFocus();
      }
    } on Object {
      _report('Could not open this photo. Try another one.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _thumbnail(Uint8List bytes, {double size = 56}) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      gaplessPlayback: true,
      semanticLabel: 'Attached photo',
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const Icon(CupertinoIcons.photo),
      ),
    ),
  );

  Widget _turnPhoto(TurnRecord turn) => FutureBuilder<Uint8List?>(
    future: _turnPhotos.putIfAbsent(
      turn.id,
      () => widget.workspace.turnPhoto(turn.id),
    ),
    builder: (context, snapshot) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: snapshot.data == null
          ? const SizedBox(width: 120, height: 120)
          : Semantics(
              button: true,
              label: 'Open photo',
              child: GestureDetector(
                onTap: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => PhotoViewer(bytes: snapshot.data!),
                  ),
                ),
                child: ExcludeSemantics(
                  child: _thumbnail(snapshot.data!, size: 120),
                ),
              ),
            ),
    ),
  );

  Future<void> _openSource(TurnEvidenceSnapshot source) async {
    try {
      final preview = await widget.knowledge.resolveCitation(source);
      if (preview == null) {
        _report(
          'Source deleted. The captured passage is still available here.',
        );
        await _load();
      } else if (mounted) {
        await widget.onPreview(preview);
      }
    } on Object {
      _report('Could not open this source.');
    }
  }

  Future<void> _openLink(Uri uri) async {
    final open = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Open external link?'),
        content: Text('This leaves Sekret and may use the network.\n\n$uri'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open link'),
          ),
        ],
      ),
    );
    if (open == true) {
      try {
        await widget.onLink(uri);
      } on Object {
        _report('Could not open this link.');
      }
    }
  }

  Future<void> _actions(TurnRecord turn) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Turn actions'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'copy'),
            child: const Text('Copy answer'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'select'),
            child: const Text('Select text'),
          ),
          if (!_busy)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'regenerate'),
              child: const Text('Regenerate'),
            ),
          if (!_busy)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete from here'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: turn.assistantText));
      return;
    }
    if (action == 'select') {
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(
              middle: Text('Select text'),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  '${turn.userText}\n\n${turn.assistantText}',
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!mounted) return;
    if (action == 'regenerate' && !_busy) {
      await _send(regenerate: turn);
      return;
    }
    if (action == 'delete' && !_busy) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Delete from here?'),
          content: const Text(
            'This turn and every later turn in this chat will be permanently deleted.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true && !_busy) {
        try {
          await widget.workspace.deleteFromTurn(turn.chatId, turn.id);
        } on Object {
          _report('Could not delete these turns.');
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _input.dispose();
    _messageFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () async {
          await Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) =>
                  ChatHistory(workspace: widget.workspace, isBusy: () => _busy),
            ),
          );
          if (mounted) {
            if (widget.workspace.currentChatId == null) {
              await _newChat();
            } else {
              await _load();
            }
          }
        },
        child: const Icon(CupertinoIcons.clock, semanticLabel: 'Chat history'),
      ),
      // The chat's own title: set from its first message, or renamed.
      middle: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sekret'),
          Text(
            _chat?.title ?? 'New Chat',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _newChat,
        child: const Icon(
          CupertinoIcons.square_pencil,
          semanticLabel: 'New Chat',
        ),
      ),
    ),
    child: SafeArea(
      child: PanelAndContent(
        panelAtBottom: true,
        content: _chat == null
            ? Center(
                child: CupertinoButton(
                  onPressed: _initialize,
                  child: const Text('Open Chat'),
                ),
              )
            : ListView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                children: [
                  if (_turns.isEmpty) _empty(),
                  for (final turn in _turns) _turn(turn),
                  if (_summary)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Earlier conversation summarized',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
        panel: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            _composer(),
          ],
        ),
      ),
    ),
  );

  Widget _empty() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      const TuckMascot(size: 120),
      const SizedBox(height: 20),
      const Text(
        'A little space to think',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Ask a question, work through an idea, or choose sources from your Knowledge Base.',
      ),
      const SizedBox(height: 20),
      CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: widget.onKnowledgeBase,
        child: const Text('Add to Knowledge Base'),
      ),
      for (final prompt in [
        'Help me organize an idea',
        'Explain something simply',
      ])
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: () => setState(() => _input.text = prompt),
          child: Text(prompt),
        ),
    ],
  );

  Widget _turn(TurnRecord turn) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: .86,
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (turn.hasPhoto) _turnPhoto(turn),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemFill.resolveFrom(
                      context,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectableText(turn.userText),
                ),
              ],
            ),
          ),
        ),
        Text(
          turn.answerLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        Text(
          ModelCatalogue.entries
                  .where((m) => m.id == turn.provenance.model.identifier)
                  .firstOrNull
                  ?.name ??
              turn.provenance.model.identifier,
          style: const TextStyle(fontSize: 12, color: SekretBrand.secondary),
        ),
        if (turn.assistantText.isNotEmpty)
          AnswerContent(text: turn.assistantText, onLink: _openLink),
        if (turn.outcome != TurnOutcome.completed &&
            turn.outcome != TurnOutcome.insufficientEvidence)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Semantics(liveRegion: true, child: Text(_status(turn))),
          ),
        if (turn.provenance.evidence.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                if (!_expandedSources.remove(turn.id)) {
                  _expandedSources.add(turn.id);
                }
              }),
              child: Text(
                '${_expandedSources.contains(turn.id) ? 'Hide' : 'Show'} sources (${turn.provenance.evidence.length})',
              ),
            ),
          ),
          if (_expandedSources.contains(turn.id))
            for (final source in turn.provenance.evidence)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.sourceTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        if (source.page != null) 'Page ${source.page}',
                        if (source.heading.isNotEmpty) source.heading,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13),
                    ),
                    SelectableText(source.passageText),
                    if (source.sourceDeleted)
                      const Text('Source deleted')
                    else
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => _openSource(source),
                        child: const Text('Open source'),
                      ),
                  ],
                ),
              ),
        ],
        if (turn.outcome != TurnOutcome.generating)
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _actions(turn),
              child: const Icon(
                CupertinoIcons.ellipsis,
                semanticLabel: 'Turn actions',
              ),
            ),
          ),
      ],
    ),
  );

  String _status(TurnRecord turn) => switch (turn.outcome) {
    TurnOutcome.generating => 'Responding…',
    TurnOutcome.stopped => 'Stopped · Response incomplete',
    TurnOutcome.interrupted => 'Interrupted · Regenerate to try again',
    TurnOutcome.failed => switch (turn.failure) {
      TurnFailure.sourcesUnavailable =>
        'Selected sources are no longer ready. Check your Knowledge Base.',
      TurnFailure.retrievalUnavailable =>
        'Could not retrieve evidence. Retry when indexing is available.',
      TurnFailure.contextOverflow =>
        'This turn exceeds the model context. Try a shorter question or start a new chat.',
      TurnFailure.deviceNotEligible =>
        'This device does not support the on-device model.',
      TurnFailure.appleIntelligenceNotEnabled =>
        'Enable Apple Intelligence in Settings to answer.',
      TurnFailure.modelNotReady || TurnFailure.unavailable =>
        'The on-device model is not ready. Try again shortly.',
      TurnFailure.guardrailViolation =>
        turn.hasPhoto
            ? 'The on-device model declined to answer about this photo.'
            : 'The on-device model could not answer this request.',
      TurnFailure.photosUnsupported =>
        'Photo questions need Apple Intelligence on iOS 27. Select it in Models, then regenerate.',
      _ => 'The response failed. Regenerate to try again.',
    },
    _ => '',
  };

  Widget _composer() => Container(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy &&
            !_turns.any((turn) => turn.outcome == TurnOutcome.generating))
          const Text(
            'Another chat is responding. Stop it before sending.',
            style: TextStyle(fontSize: 13),
          ),
        if (_chat?.mode == ChatMode.knowledgeBase &&
            _chat!.selectedSourceIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Answers only from selected sources',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
        if (_chat?.mode == ChatMode.knowledgeBase) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final id in _chat!.selectedSourceIds) _sourceChip(id),
              ],
            ),
          ),
        ],
        if (_photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _thumbnail(_photo!),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _photoBlocker ??
                        'Ask one question about this photo. Answers are the model’s interpretation and can be wrong.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: _busy ? null : () => setState(() => _photo = null),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 22,
                    semanticLabel: 'Remove photo',
                  ),
                ),
              ],
            ),
          ),
        if (_importing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Adding source…', style: TextStyle(fontSize: 13)),
          ),
        if (_availability is! Available)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(switch (_availability) {
                DeviceNotEligible() =>
                  'On-device answers are unsupported on this device.',
                AppleIntelligenceNotEnabled() =>
                  'Enable Apple Intelligence to answer.',
                ModelNotReady() => 'The on-device model is not ready.',
                ModelLoading() =>
                  'The on-device model is loading. Give it a minute.',
                _ => 'Checking on-device model…',
              }, style: const TextStyle(fontSize: 13)),
              CupertinoButton(
                onPressed: _checkAvailability,
                child: const Text('Retry'),
              ),
              if (_availability is AppleIntelligenceNotEnabled &&
                  widget.onSettings != null)
                CupertinoButton(
                  onPressed: widget.onSettings,
                  child: const Text('Open Settings'),
                ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              onPressed:
                  _chat == null ||
                      _busy ||
                      _importing ||
                      _changingSources ||
                      _choosingSources
                  ? null
                  : _addSource,
              child: const Icon(
                CupertinoIcons.paperclip,
                semanticLabel: 'Add sources',
              ),
            ),
            Expanded(
              child: TextFieldTapRegion(
                groupId: _messageFocus,
                // Dismiss on release so controls do not move before their tap
                // finishes. Unfocus only the composer, not selectable answers.
                onTapUpOutside: (_) => _messageFocus.unfocus(),
                child: CupertinoTextField(
                  controller: _input,
                  focusNode: _messageFocus,
                  groupId: _messageFocus,
                  placeholder: _photo == null
                      ? 'Message'
                      : 'Ask about this photo',
                  minLines: 1,
                  maxLines: 4,
                  enabled: _availability is Available,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              onPressed: _busy
                  ? () async {
                      await widget.engine.stop();
                      if (mounted) setState(() {});
                    }
                  : _chat != null &&
                        !_importing &&
                        !_changingSources &&
                        !_choosingSources &&
                        _availability is Available &&
                        _sourcesReady &&
                        (_photo == null || _photoReady) &&
                        _input.text.trim().isNotEmpty
                  ? () => _send()
                  : null,
              child: Icon(
                _busy
                    ? CupertinoIcons.stop_circle
                    : CupertinoIcons.arrow_up_circle_fill,
                size: 30,
                semanticLabel: _busy ? 'Stop' : 'Send',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sourceChip(String id) {
    final item = _items.where((item) => item.id == id).firstOrNull;
    final status = item == null
        ? 'Source deleted'
        : processingLabel(item.processingState);
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .65,
      ),
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.title ?? 'Unavailable source',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(status, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(left: 8),
            onPressed:
                _busy || _changingSources || _importing || _choosingSources
                ? null
                : () {
                    final chat = _chat!;
                    _scope(
                      chat.id,
                      chat.selectedSourceIds
                          .where((source) => source != id)
                          .toList(),
                    );
                  },
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 18,
              semanticLabel: 'Remove ${item?.title ?? 'unavailable source'}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen, zoomable view of a photo retained with a turn.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.black,
    navigationBar: CupertinoNavigationBar(
      backgroundColor: CupertinoColors.black,
      brightness: Brightness.dark,
      middle: const Text(
        'Photo',
        style: TextStyle(color: CupertinoColors.white),
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    ),
    child: SafeArea(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            semanticLabel: 'Photo',
            errorBuilder: (_, _, _) => const Text(
              'This photo can’t be shown.',
              style: TextStyle(color: CupertinoColors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
