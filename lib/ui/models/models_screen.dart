import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/models/model_catalogue.dart';
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
    this.store,
    this.selection,
    this.supportsLocalModel,
  });

  final LlmBackend model;
  final Future<void> Function() openSystemSettings;
  final ModelStore? store;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    widget.store?.addListener(_changed);
    widget.selection?.addListener(_changed);
    _checkLocal();
  }

  @override
  void didUpdateWidget(covariant ModelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) _refresh();
    if (oldWidget.store != widget.store ||
        oldWidget.selection != widget.selection) {
      oldWidget.store?.removeListener(_changed);
      oldWidget.selection?.removeListener(_changed);
      widget.store?.addListener(_changed);
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
    widget.store?.removeListener(_changed);
    widget.selection?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _checkLocal() async {
    if (widget.store == null) return;
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

  Future<void> _download() async {
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Download Qwen · 2.08 GB?'),
        content: const Text(
          'Hugging Face and its delivery hosts see your IP address and model choice, never chats or sources. Needs 2.62 GB free; Wi-Fi recommended. Downloads continue while locked. Return to Sekret for verification. Cancel discards progress.',
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
    await _run(() async {
      final store = widget.store!;
      if (!store.initialized) await store.initialize();
      await store.install();
    });
  }

  Future<void> _remove() async {
    final switchesModel = widget.selection?.selected == ModelCatalogue.qwen.id;
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Remove downloaded model?'),
        content: Text(
          '${switchesModel ? 'Switch to Apple Intelligence and remove Qwen’s downloaded files? ' : ''}'
          '${switchesModel && _availability is! Available ? 'Apple Intelligence is not ready; chat will be unavailable until it is ready or you select another available model. ' : ''}'
          'Your chats and Knowledge Vault stay intact. You can download Qwen again later.',
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
      final selection = widget.selection;
      if (selection?.selected == ModelCatalogue.qwen.id) {
        // Never remove an active lease or silently change the model. If the
        // choice changed while the dialog was open, ask again next time.
        if (!switchesModel) throw StateError('Model selection changed');
        await selection!.select(ModelCatalogue.apple.id);
      }
      await widget.store!.remove();
    });
  }

  Future<void> _licenses() => _run(() async {
    final qwen = await rootBundle.loadString(
      'assets/licenses/Qwen-Apache-2.0.txt',
    );
    final runtime = await rootBundle.loadString(
      'assets/licenses/llama-MIT.txt',
    );
    if (!mounted) return;
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
                'Text chat only: no images or Knowledge Vault answers. Runs entirely on this iPhone after download. Answers may stop if the phone gets too hot. To remove it while it is selected, switch to Apple Intelligence first.\n\n'
                'License and provenance\n\nQwen3-4B-Instruct-2507 by Qwen\nQ3_K_M quantization by Unsloth\n'
                'Publisher license revision: cdbee75f17c01a7cc42f958dc650907174af0554\n'
                'Artifact revision: ${ModelCatalogue.qwen.artifact!.revision}\n'
                'SHA-256: ${ModelCatalogue.qwen.artifact!.sha256}\n\n$qwen\n\n'
                'llama.cpp b11429 · d81235049384534c167caea52b85a694f6103d14\n\n$runtime',
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

  Future<void> _appleInfo() => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('Apple Intelligence'),
      content: Text(
        'Built into iOS and runs on this iPhone. Sekret does not download or remove it.\n\n'
        'Answers text chats and Knowledge Vault questions. On iOS 27 it can also answer one question about a photo; it may misread small or cut-off text and does not count objects.\n\n'
        'The system model may change with iOS updates.',
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
    final models = ModelCatalogue.entries.where(
      (model) => model.name.toLowerCase().contains(_query.trim().toLowerCase()),
    );
    return CupertinoPageScaffold(
      backgroundColor: SekretBrand.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('Models')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _intro(),
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
    final apple = model.kind == CatalogueModelKind.appleManaged;
    final photos = model.capabilities.contains(ModelCapability.photoQuestions);
    final ratings = ModelRatings.forModel(model.id);
    final store = widget.store;
    final state = store?.state;
    final installed = state?.phase == ModelInstallPhase.installed;
    final selected = widget.selection?.selected == model.id;
    final active =
        selected && (apple || (widget.selection?.hasLocalLease ?? false));
    final busy = _working || (widget.selection?.busy ?? false);
    final selectable =
        !busy &&
        !active &&
        widget.selection != null &&
        (apple
            ? _availability is Available
            : installed && _localSupported == true);
    final status = apple
        ? (_checking
              ? 'Checking readiness…'
              : _error ??
                    (_availability is Available
                        ? 'Built into iOS'
                        : modelStatus(_availability)))
        : store == null
        ? 'Not available in this version'
        : switch (state!.phase) {
            ModelInstallPhase.absent =>
              _localSupported == false
                  ? 'Device not supported'
                  : 'Open model · 2.08 GB download',
            ModelInstallPhase.downloading =>
              'Downloading · ${(100 * state.receivedBytes / store.model.artifact!.bytes).clamp(0, 100).toStringAsFixed(0)}%',
            ModelInstallPhase.verifying => 'Verifying…',
            ModelInstallPhase.installed =>
              selected && !active
                  ? 'Downloaded · Tap the circle to use'
                  : 'Open model · 2.08 GB download',
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
                      ? () => _run(() => widget.selection!.select(model.id))
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
                      Text(
                        model.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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
                apple ? _appleInfo : _licenses,
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
                        photos
                            ? CupertinoIcons.photo
                            : CupertinoIcons.textformat,
                        size: 18,
                        color: SekretBrand.secondary,
                        semanticLabel: photos
                            ? 'Photo questions supported on iOS 27'
                            : 'Text only; no photo questions',
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        photos ? 'Text and photos (iOS 27)' : 'Text only',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SekretBrand.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (apple) ...[
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
                    onPressed: busy || _localSupported != true
                        ? null
                        : _download,
                    child: const Text(
                      'Download · 2.08 GB',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                if (!state.busy &&
                    (installed || state.phase == ModelInstallPhase.failed))
                  _icon(
                    'Remove downloaded files',
                    CupertinoIcons.trash,
                    busy ? null : _remove,
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
            : label}: ${score == null ? 'not measured' : '$score out of 5, held-out test'}',
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
            score == null ? 'Not measured' : '$score/5',
            style: const TextStyle(fontSize: 10, color: SekretBrand.secondary),
          ),
        ],
      ),
    ),
  );
}
