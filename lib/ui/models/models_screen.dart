import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/models/model_catalogue.dart';
import '../../core/models/model_library.dart';
import '../../core/models/model_ratings.dart';
import '../../core/models/model_store.dart';
import '../../core/models/model_selection.dart';
import '../../core/models/model_download.dart';
import '../../core/platform/local_model_backend.dart';
import '../../core/platform/llm_backend.dart';
import '../sekret_brand.dart';
import '../settings/settings_screen.dart' show modelStatus;

/// Compact reviewed catalogue with explicit installation and model selection.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({
    super.key,
    required this.model,
    required this.openSystemSettings,
    this.library,
    this.selection,
    this.supportsLocalModel,
    this.catalogue = ModelCatalogue.entries,
  });

  final LlmBackend model;
  final Future<void> Function() openSystemSettings;
  final ModelLibrary? library;

  /// Reviewed entries to offer; tests pass a fixture catalogue.
  final List<CatalogueModel> catalogue;
  final ModelSelection? selection;
  final Future<bool> Function()? supportsLocalModel;

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen>
    with WidgetsBindingObserver {
  LlmAvailability? _availability;
  String _query = '';
  String? _error;
  int _revision = 0;
  bool _checking = false;
  bool _openingSettings = false;
  bool _working = false;
  bool? _localSupported;
  String? _operationError;
  ModelKind _kind = ModelKind.chat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    widget.library?.addListener(_changed);
    widget.selection?.addListener(_changed);
    _checkLocal();
  }

  @override
  void didUpdateWidget(covariant ModelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) _refresh();
    if (oldWidget.library != widget.library ||
        oldWidget.selection != widget.selection) {
      oldWidget.library?.removeListener(_changed);
      oldWidget.selection?.removeListener(_changed);
      widget.library?.addListener(_changed);
      widget.selection?.addListener(_changed);
      _checkLocal();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    widget.library?.removeListener(_changed);
    widget.selection?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _checkLocal() async {
    if (widget.library == null) return;
    final supported =
        await (widget.supportsLocalModel ??
            LocalModelBackend.deviceSupported)();
    if (mounted) setState(() => _localSupported = supported);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _operationError = null;
    });
    try {
      await action();
    } on ModelOperationCancelled {
      // The store reports cancellation; an explicit Stop is not a failure.
    } on Object {
      if (mounted) {
        setState(
          () => _operationError =
              'Could not finish. Stop any response, check storage and connection, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download(CatalogueModel model) async {
    final size = formatModelSize(model.totalBytes);
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Download ${model.name}?'),
        content: Text(
          '$size${model.notice == null ? '' : ' · ${model.notice!.license}'}. '
          'Hugging Face and its delivery hosts see your IP address and model choice, never chats or sources. '
          'Needs ${formatModelSize(model.totalBytes + ModelStore.freeSpaceReserve)} free; Wi-Fi recommended. '
          'Downloads continue while locked. Return to Sekret for verification. Cancel discards progress.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() => widget.library!.install(model.id));
  }

  Future<void> _remove(CatalogueModel model) async {
    final selection = widget.selection;
    final chat = model.kind == ModelKind.chat;
    final switchesModel = selection?.selectedFor(model.kind) == model.id;
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Remove downloaded model?'),
        content: Text(
          '${switchesModel ? (chat ? 'Switch to Apple Intelligence and remove ${model.name}’s downloaded files? ' : 'Turn off ${model.name} and remove its downloaded files? ') : ''}'
          '${switchesModel && chat && _availability is! Available ? 'Apple Intelligence is not ready; chat will be unavailable until it is ready or you select another available model. ' : ''}'
          'Your chats and Knowledge Vault stay intact. You can download ${model.name} again later.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(switchesModel ? 'Switch & remove' : 'Remove'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      if (selection?.selectedFor(model.kind) == model.id) {
        // Never remove an active lease or silently change the model. If the
        // choice changed while the dialog was open, ask again next time.
        if (!switchesModel) throw StateError('Model selection changed');
        if (chat) {
          await selection!.select(ModelCatalogue.apple.id);
        } else {
          await selection!.choose(model.kind, null);
        }
      }
      await widget.library!.store(model.id)!.remove();
    });
  }

  Future<void> _licenses(CatalogueModel model) => _run(() async {
    final notice = model.notice;
    final runtime = ModelCatalogue.runtimeNotices[model.runtime];
    final texts = [
      for (final asset in [...?notice?.assets, ?runtime?.asset])
        await rootBundle.loadString(asset),
    ];
    if (!mounted) return;
    final files = model.artifacts;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Model notices'),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                '${model.summary} To remove it while it is selected, switch away from it first.\n\n'
                'License and provenance\n\n'
                '${notice == null ? '' : '${notice.credit}\nLicense: ${notice.license}\n'}'
                '${notice?.attribution == null ? '' : '${notice!.attribution}\n'}'
                'Artifact revision: ${files.first.revision}\n'
                '${files.length == 1 ? 'SHA-256: ${files.single.sha256}' : '${files.length} files · ${formatModelSize(model.totalBytes)}, each checked by SHA-256'}\n\n'
                '${texts.isEmpty ? '' : texts.first}'
                '${runtime == null ? '' : '\n\n${runtime.credit}\n\n${texts.last}'}',
              ),
            ),
          ),
        ),
      ),
    );
  });

  Future<void> _refresh() async {
    final revision = ++_revision;
    setState(() {
      _checking = true;
      _availability = null;
      _error = null;
    });
    try {
      final availability = await widget.model.availability();
      if (!mounted || revision != _revision) return;
      setState(() => _availability = availability);
    } on Object {
      if (!mounted || revision != _revision) return;
      setState(() => _error = 'Could not check model readiness. Try again.');
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openSettings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    try {
      await widget.openSystemSettings();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not open iOS Settings. Try again.');
      }
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  Future<void> _appleInfo(CatalogueModel model) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(model.name),
      content: Text(
        model.kind == ModelKind.chat
            ? '${model.summary}\n\n'
                  'Answers text chats and Knowledge Vault questions. On iOS 27 it can also answer one question about a photo; it may misread small or cut-off text and does not count objects.\n\n'
                  'The system model may change with iOS updates.'
            : model.summary,
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  Future<void> _ratingScale() => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Rating scale')),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Text(ModelRatingScale.explanation),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final kind in ModelKind.values)
        if (widget.catalogue.any((model) => model.kind == kind)) kind,
    ];
    final kind = kinds.contains(_kind) ? _kind : ModelKind.chat;
    final models = widget.catalogue.where(
      (model) =>
          model.kind == kind &&
          model.name.toLowerCase().contains(_query.trim().toLowerCase()),
    );
    return CupertinoPageScaffold(
      backgroundColor: SekretBrand.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('Models')),
      child: SafeArea(
        // Tapping outside the search field or scrolling dismisses the keyboard.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _intro(),
              if (kinds.length > 1) ...[
                const SizedBox(height: 16),
                CupertinoSlidingSegmentedControl<ModelKind>(
                  groupValue: kind,
                  onValueChanged: (value) {
                    if (value != null) setState(() => _kind = value);
                  },
                  children: {
                    for (final kind in kinds)
                      kind: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(switch (kind) {
                          ModelKind.chat => 'Chat',
                          ModelKind.voiceInput => 'Voice input',
                          ModelKind.readAloud => 'Read aloud',
                        }),
                      ),
                  },
                ),
              ],
              const SizedBox(height: 16),
              CupertinoSearchTextField(
                placeholder: 'Search models',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              if (_operationError != null) _notice(_operationError!),
              if (widget.selection?.selected == 'unavailable')
                _notice('Choose a model to restore your saved selection.'),
              for (final model in models) _modelRow(model),
              if (models.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching models'),
                ),
              const SizedBox(height: 4),
              CupertinoButton(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
                onPressed: _ratingScale,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.info_circle, size: 14),
                    SizedBox(width: 6),
                    Text('How ratings work', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What every model here shares, above the choice itself.
  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Choose your model',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const Text(
        'Pick whichever you like and switch anytime. Every model runs entirely on this iPhone.',
        style: TextStyle(fontSize: 15, color: SekretBrand.secondary),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label) in const [
            (CupertinoIcons.wifi_slash, 'Offline'),
            (CupertinoIcons.gift, 'Free'),
            (CupertinoIcons.lock_fill, 'Private'),
          ])
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: SekretBrand.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: SekretBrand.accent),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SekretBrand.accent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: SekretBrand.secondary),
      ),
    ),
  );

  Widget _modelRow(CatalogueModel model) {
    final apple = model.runtime == ModelRuntime.apple;
    final chat = model.kind == ModelKind.chat;
    final photos = model.capabilities.contains(ModelCapability.photoQuestions);
    final ratings = ModelRatings.forModel(model.id);
    final store = widget.library?.store(model.id);
    final state = store?.state;
    final installed = state?.phase == ModelInstallPhase.installed;
    final size = formatModelSize(model.totalBytes);
    final supported =
        model.runtime != ModelRuntime.llamaCpp || _localSupported == true;
    final selection = widget.selection;
    final selected = selection?.selectedFor(model.kind) == model.id;
    final active =
        selected && (!chat || apple || (selection?.hasLocalLease ?? false));
    final busy = _working || (selection?.busy ?? false);
    final selectable =
        !busy &&
        selection != null &&
        (chat ? !active : true) &&
        (apple
            ? (!chat || _availability is Available)
            : installed && supported);
    final status = apple
        ? (!chat
              ? 'Built into iOS'
              : _checking
              ? 'Checking readiness…'
              : _error ??
                    (_availability is Available
                        ? 'Built into iOS'
                        : modelStatus(_availability)))
        : store == null
        ? 'Not available in this version'
        : switch (state!.phase) {
            ModelInstallPhase.absent =>
              model.runtime == ModelRuntime.llamaCpp && _localSupported == false
                  ? 'Device not supported'
                  : 'Open model · $size download',
            ModelInstallPhase.downloading =>
              'Downloading · ${(100 * state.receivedBytes / model.totalBytes).clamp(0, 100).toStringAsFixed(0)}%',
            ModelInstallPhase.verifying => 'Verifying…',
            ModelInstallPhase.installed =>
              (selected && !active) || (!selected && !chat)
                  ? 'Downloaded · Tap the circle to use'
                  : 'Open model · $size download',
            ModelInstallPhase.removing => 'Removing…',
            ModelInstallPhase.failed => state.message ?? 'Download failed',
          };
    return Container(
      key: ValueKey(model.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 10),
      decoration: BoxDecoration(
        color: SekretBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? SekretBrand.accent : SekretBrand.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'Select ${model.name}',
                selected: selected,
                button: true,
                child: CupertinoButton(
                  padding: const EdgeInsets.all(10),
                  onPressed: selectable
                      ? () => _run(
                          () => chat
                              ? selection.select(model.id)
                              : selection.choose(
                                  model.kind,
                                  selected ? null : model.id,
                                ),
                        )
                      : null,
                  child: Icon(
                    selected
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 22,
                    color: selected
                        ? SekretBrand.accent
                        : SekretBrand.secondary,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            model.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (model.isNew)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SekretBrand.accent.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'New',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: SekretBrand.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SekretBrand.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _icon(
                'About ${model.name}',
                CupertinoIcons.info_circle,
                () => apple ? _appleInfo(model) : _licenses(model),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    MediaQuery.textScalerOf(context).scale(12) <= 18 &&
                    constraints.maxWidth >= 300;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (label, score) in [
                      ('Quality', ratings?.quality),
                      ('Speed', ratings?.speed),
                      ('Memory', null),
                      ('Battery', null),
                    ])
                      SizedBox(
                        width:
                            (constraints.maxWidth - (wide ? 36 : 12)) /
                            (wide ? 4 : 2),
                        child: _rating(label, score),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        switch (model.kind) {
                          ModelKind.voiceInput => CupertinoIcons.mic,
                          ModelKind.readAloud => CupertinoIcons.speaker_2,
                          ModelKind.chat =>
                            photos
                                ? CupertinoIcons.photo
                                : CupertinoIcons.textformat,
                        },
                        size: 18,
                        color: SekretBrand.secondary,
                        semanticLabel: switch (model.kind) {
                          ModelKind.voiceInput => 'Turns speech into text',
                          ModelKind.readAloud => 'Reads answers aloud',
                          ModelKind.chat =>
                            photos
                                ? 'Photo questions supported on iOS 27'
                                : 'Text only; no photo questions',
                        },
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        switch (model.kind) {
                          ModelKind.voiceInput => 'Speech to text',
                          ModelKind.readAloud => 'Text to speech',
                          ModelKind.chat =>
                            photos ? 'Text and photos (iOS 27)' : 'Text only',
                        },
                        style: const TextStyle(
                          fontSize: 12,
                          color: SekretBrand.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (apple && chat) ...[
                CupertinoButton(
                  onPressed: _checking || _availability is Available
                      ? null
                      : _refresh,
                  child: Text(
                    _checking
                        ? 'Checking…'
                        : _availability is Available
                        ? 'Ready'
                        : 'Check readiness',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (_availability is AppleIntelligenceNotEnabled ||
                    _availability is ModelNotReady)
                  CupertinoButton(
                    onPressed: _openingSettings ? null : _openSettings,
                    child: const Text(
                      'Open iOS Settings',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ] else if (store != null) ...[
                if (state!.busy)
                  _icon(
                    'Cancel download',
                    CupertinoIcons.xmark_circle,
                    store.cancel,
                  )
                else if (!installed)
                  CupertinoButton(
                    onPressed: busy || !supported
                        ? null
                        : () => _download(model),
                    child: Text(
                      'Download · $size',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                if (!state.busy &&
                    (installed || state.phase == ModelInstallPhase.failed))
                  _icon(
                    'Remove downloaded files',
                    CupertinoIcons.trash,
                    busy ? null : () => _remove(model),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _icon(String label, IconData icon, VoidCallback? action) => Semantics(
    label: label,
    button: true,
    child: CupertinoButton(
      padding: const EdgeInsets.all(10),
      onPressed: action,
      child: Icon(icon, size: 20),
    ),
  );

  Widget _rating(String label, int? score) => Semantics(
    container: true,
    label:
        '${label == 'Quality'
            ? 'Answer quality'
            : label == 'Memory'
            ? 'Memory efficiency'
            : label == 'Battery'
            ? 'Battery efficiency'
            : label}: ${score == null ? (label == 'Memory' ? 'not scored; see how ratings work' : 'not measured') : '$score out of 5, held-out test'}',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: SekretBrand.secondary),
          ),
          const SizedBox(height: 5),
          Row(
            children: List.generate(
              5,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 4 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: score != null && index < score
                        ? SekretBrand.accent
                        : SekretBrand.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            score == null
                ? (label == 'Memory' ? 'Not scored' : 'Not measured')
                : '$score/5',
            style: const TextStyle(fontSize: 10, color: SekretBrand.secondary),
          ),
        ],
      ),
    ),
  );
}

/// Decimal units, as iOS Settings shows storage.
String formatModelSize(int bytes) {
  if (bytes >= 1000000000) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  if (bytes >= 1000000) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '<1 MB';
}
