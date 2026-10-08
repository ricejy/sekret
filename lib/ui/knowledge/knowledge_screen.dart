import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../sekret_brand.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../core/storage/local_data_vault.dart';
import '../../core/platform/pdf_file_picker.dart';
import '../../core/platform/document_image_picker.dart';
import '../../core/platform/file_selector_pdf_picker.dart';
import '../../core/platform/photos_document_image_picker.dart';
import 'source_status.dart';
import 'source_preview.dart';
import 'knowledge_import_actions.dart';
import 'rename_sheet.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({
    super.key,
    required this.knowledge,
    this.pdfPicker = const FileSelectorPdfPicker(),
    this.imagePicker = const PhotosDocumentImagePicker(),
  });
  final KnowledgeBase knowledge;
  final PdfFilePicker pdfPicker;
  final DocumentImagePicker imagePicker;
  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  final _search = TextEditingController();
  StreamSubscription<void>? _changes;
  List<CatalogueMatch>? _matches;
  KnowledgeSourceType? _type;
  String? _error;
  String? _loadError;
  Timer? _debounce;
  int _revision = 0;
  bool _importing = false;
  final _busy = <String>{};

  void _startProcessing(String id) {
    // KnowledgeBase owns the long-running job. Do not disable Cancel/Delete
    // for its entire duration; those actions coordinate a safe stop themselves.
    unawaited(
      widget.knowledge
          .process(id)
          .then<void>(
            (_) {},
            onError: (Object _) {
              if (mounted) {
                setState(
                  () => _error =
                      'Indexing could not finish. Retry from the source actions.',
                );
              }
            },
          ),
    );
  }

  Future<void> _perform(
    KnowledgeItemRecord item,
    Future<void> Function() action,
  ) async {
    if (_busy.contains(item.id)) return;
    setState(() {
      _busy.add(item.id);
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'The action could not finish. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(item.id));
        await _load();
      }
    }
  }

  Future<void> _rename(KnowledgeItemRecord item) async {
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => RenameKnowledge(title: item.title),
    );
    if (mounted && title != null) {
      await _perform(item, () => widget.knowledge.rename(item.id, title));
    }
  }

  Future<void> _delete(KnowledgeItemRecord item) async {
    final ready = item.processingState == KnowledgeProcessingState.indexed;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete “${item.title}”?'),
        content: Text(
          ready
              ? 'The source and its search index are removed from this iPhone. Chats keep their text, and citations show Source deleted.'
              : 'The source and any partial work are removed from this iPhone.',
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
    if (mounted && confirmed == true) {
      await _perform(
        item,
        () => ready
            ? widget.knowledge.delete(item.id)
            : widget.knowledge.cancelImport(item.id),
      );
    }
  }

  Future<void> _actions(KnowledgeItemRecord item) async {
    final status = SourceStatus.of(item.processingState);
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(item.title),
        message: status == SourceStatus.failed
            ? Text(item.processingMessage ?? 'Could not be added.')
            : null,
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'rename'),
            child: const Text('Rename'),
          ),
          if (status == SourceStatus.failed)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'retry'),
              child: const Text('Retry'),
            ),
          if (status == SourceStatus.ready)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'reindex'),
              child: const Text('Re-index'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        await _rename(item);
      case 'delete':
        await _delete(item);
      case 'retry':
        _startProcessing(item.id);
      case 'reindex':
        final confirmed = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Re-index this source?'),
            content: const Text(
              'The original stays available. This source cannot support new answers until indexing finishes.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Re-index'),
              ),
            ],
          ),
        );
        if (mounted && confirmed == true) {
          await _perform(item, () async {
            await widget.knowledge.invalidateIndex(item.id);
            _startProcessing(item.id);
          });
        }
    }
  }

  Future<void> _open(KnowledgeLocation location) async {
    try {
      final preview = await widget.knowledge.preview(location);
      if (!mounted) return;
      if (preview == null) {
        setState(() => _error = 'Source deleted.');
        return;
      }
      await Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) =>
              SourcePreview(knowledge: widget.knowledge, location: location),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not open this source. Try again.');
      }
    }
  }

  Future<void> _add() async {
    if (_importing) return;
    final type = await showCupertinoModalPopup<KnowledgeSourceType>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Add to Knowledge Vault'),
        message: const Text('Your source stays on this device.'),
        actions: [
          for (final type in KnowledgeSourceType.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, type),
              child: Text(switch (type) {
                KnowledgeSourceType.pastedText => 'Paste text',
                KnowledgeSourceType.pdf => 'Choose PDF',
                KnowledgeSourceType.photo => 'Choose photograph',
              }),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || type == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await importKnowledgeSource(
        context,
        widget.knowledge,
        type,
        pdfPicker: widget.pdfPicker,
        imagePicker: widget.imagePicker,
      );
      if (!mounted || result == null) return;
      if (result.duplicate) {
        final open = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Already in your Knowledge Vault'),
            content: Text(
              'This content is already saved as “${result.item.title}”. No second copy was added.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep existing'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open existing'),
              ),
            ],
          ),
        );
        if (mounted && open == true) {
          await _open(KnowledgeLocation(result.item.id));
        }
      } else {
        // An active filter must not hide the item that was just admitted.
        _search.clear();
        _type = null;
        await _load();
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Import could not finish. Check the source and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _changes = widget.knowledge.changes.listen(
      (_) => _load(),
      onError: (Object _) => _load(),
    );
    _load();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    try {
      final matches = await widget.knowledge.catalogue(
        query: _search.text,
        sourceType: _type,
      );
      if (mounted && revision == _revision) {
        setState(() {
          _matches = matches;
          _loadError = null;
        });
      }
    } on Object {
      if (mounted && revision == _revision) {
        setState(
          () => _loadError = 'Could not load the Knowledge Vault. Try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => _search.text.isNotEmpty || _type != null;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: SekretBrand.background,
    navigationBar: CupertinoNavigationBar(
      middle: const Text('Knowledge Vault'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _importing ? null : _add,
        child: const Icon(CupertinoIcons.add, semanticLabel: 'Add knowledge'),
      ),
    ),
    child: SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              sliver: SliverList.list(children: _header()),
            ),
            if (_matches == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_matches!.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.separated(
                  itemCount: _matches!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _card(_matches![index]),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _header() => [
    // An empty vault has nothing to search or filter yet.
    if (_filtered || (_matches?.isNotEmpty ?? false)) ..._controls(),
    if (_error != null || _loadError != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          onPressed: () {
            setState(() => _error = null);
            _load();
          },
          child: Text(
            _error ?? _loadError!,
            style: const TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemRed,
            ),
          ),
        ),
      ),
    if (_matches != null && _matches!.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          '${_matches!.length} ${_matches!.length == 1 ? 'item' : 'items'}',
          style: const TextStyle(fontSize: 13, color: SekretBrand.secondary),
        ),
      ),
  ];

  List<Widget> _controls() => [
    CupertinoSearchTextField(
      controller: _search,
      placeholder: 'Search your vault',
      onChanged: (_) {
        ++_revision;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 180), _load);
      },
    ),
    const SizedBox(height: 12),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (type, label) in const [
            (null, 'All'),
            (KnowledgeSourceType.pastedText, 'Text'),
            (KnowledgeSourceType.pdf, 'PDFs'),
            (KnowledgeSourceType.photo, 'Photos'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(label, type),
            ),
        ],
      ),
    ),
  ];

  Widget _chip(String label, KnowledgeSourceType? type) {
    final selected = _type == type;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          setState(() => _type = type);
          _load();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? SekretBrand.accent : SekretBrand.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? SekretBrand.accent : SekretBrand.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: selected ? SekretBrand.background : SekretBrand.foreground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _filtered
          ? const [
              Icon(
                CupertinoIcons.search,
                size: 36,
                color: SekretBrand.secondary,
              ),
              SizedBox(height: 12),
              Text('No matching items', textAlign: TextAlign.center),
            ]
          : [
              const TuckMascot(size: 140, asset: 'assets/brand/tuck-shell.png'),
              const SizedBox(height: 16),
              const Text(
                'Your vault is empty',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add notes, PDFs or photos of documents. Sekret answers from them, and they never leave this iPhone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SekretBrand.secondary),
              ),
              const SizedBox(height: 20),
              CupertinoButton.filled(
                onPressed: _importing ? null : _add,
                child: const Text('Add to Vault'),
              ),
            ],
    ),
  );

  Widget _card(CatalogueMatch match) {
    final item = match.item;
    final status = SourceStatus.of(item.processingState);
    final busy = _busy.contains(item.id);
    final meta = [
      sourceTypeLabel(item.sourceType),
      sourceSizeLabel(item.sourceSize),
      if (item.sourceType == KnowledgeSourceType.pdf && item.pageCount > 0)
        '${item.pageCount} ${item.pageCount == 1 ? 'page' : 'pages'}',
      importDateLabel(item.createdAt),
    ].join(' · ');
    final radius = BorderRadius.circular(16);
    return Dismissible(
      key: ValueKey(item.id),
      confirmDismiss: (direction) async {
        if (!busy) {
          if (direction == DismissDirection.startToEnd) {
            await _rename(item);
          } else {
            await _delete(item);
          }
        }
        return false;
      },
      background: _swipe(radius, 'Rename', SekretBrand.accent, left: true),
      secondaryBackground: _swipe(
        radius,
        'Delete',
        CupertinoColors.systemRed,
        left: false,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: SekretBrand.surface,
          borderRadius: radius,
          border: Border.all(
            color: status == SourceStatus.failed
                ? CupertinoColors.systemRed.withValues(alpha: .45)
                : SekretBrand.line,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CupertinoButton(
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                onPressed: () =>
                    _open(match.location ?? KnowledgeLocation(item.id)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _typeTile(item.sourceType),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: SekretBrand.foreground,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            meta,
                            style: const TextStyle(
                              fontSize: 13,
                              color: SekretBrand.secondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SourceStatusBadge(
                            status,
                            progress: switch (item.checkpoint) {
                              final c? when c.totalUnits > 0 =>
                                c.completedUnits / c.totalUnits,
                              _ => null,
                            },
                          ),
                          if (status == SourceStatus.failed &&
                              item.processingMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                item.processingMessage!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SekretBrand.secondary,
                                ),
                              ),
                            ),
                          if (match.excerpt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                match.excerpt!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SekretBrand.foreground,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.fromLTRB(8, 10, 10, 8),
              onPressed: busy ? null : () => _actions(item),
              child: Icon(
                CupertinoIcons.ellipsis,
                size: 20,
                color: SekretBrand.secondary,
                semanticLabel: 'Actions for ${item.title}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTile(KnowledgeSourceType type) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: SekretBrand.accent.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(
      switch (type) {
        KnowledgeSourceType.pastedText => CupertinoIcons.text_alignleft,
        KnowledgeSourceType.pdf => CupertinoIcons.doc_text,
        KnowledgeSourceType.photo => CupertinoIcons.photo,
      },
      size: 20,
      color: SekretBrand.accent,
    ),
  );

  Widget _swipe(
    BorderRadius radius,
    String label,
    Color color, {
    required bool left,
  }) => Container(
    decoration: BoxDecoration(color: color, borderRadius: radius),
    alignment: left ? Alignment.centerLeft : Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: left ? SekretBrand.background : CupertinoColors.white,
      ),
    ),
  );
}
