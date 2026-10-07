import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/models/model_catalogue.dart';
import '../../core/models/model_store.dart';
import '../../core/models/model_selection.dart';
import '../../core/models/model_download.dart';
import '../../core/platform/local_model_backend.dart';
import '../../core/platform/llm_backend.dart';
import '../sekret_brand.dart';
import '../settings/settings_screen.dart' show modelStatus;

/// Reports installed capabilities only; no download or compatibility is implied.
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
          'Hugging Face and its delivery hosts see your IP address and model choice, not your chats or Knowledge Base. Requires 2.62 GB free. Keep Sekret open; cancellation discards partial progress. Wi-Fi recommended. Answers then run offline.',
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
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Remove downloaded model?'),
        content: const Text(
          'Only Qwen’s downloaded files are removed. Your chats and Knowledge Base stay intact. You can download it again later.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await _run(widget.store!.remove);
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
                'Qwen3-4B-Instruct-2507 by Qwen\nQ3_K_M quantization by Unsloth\n'
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

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: SekretBrand.background,
    navigationBar: const CupertinoNavigationBar(middle: Text('Models')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          const Text(
            'Intelligence on your device',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            widget.store == null
                ? 'Sekret currently uses Apple Foundation Models for generation.'
                : 'Choose the model for future answers. Existing chats retain their original model labels. No automatic fallback.',
            style: const TextStyle(color: SekretBrand.secondary),
          ),
          const SizedBox(height: 24),
          if (_operationError != null) Text(_operationError!),
          if (widget.selection?.selected == 'unavailable')
            const Text(
              'The saved model choice could not be restored. Choose a model explicitly to continue.',
            ),
          _card(
            title: ModelCatalogue.apple.name,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? modelStatus(_availability),
                  style: const TextStyle(color: SekretBrand.secondary),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.selection != null)
                CupertinoButton(
                  onPressed:
                      _working ||
                          widget.selection!.busy ||
                          widget.selection!.selected == ModelCatalogue.apple.id
                      ? null
                      : () => _run(
                          () =>
                              widget.selection!.select(ModelCatalogue.apple.id),
                        ),
                  child: Text(
                    widget.selection!.selected == ModelCatalogue.apple.id
                        ? 'Selected'
                        : 'Use Apple Intelligence',
                  ),
                ),
              const Text(
                'Managed by iOS. Sekret does not download or remove this model.',
                style: TextStyle(color: SekretBrand.secondary),
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: _checking ? null : _refresh,
                child: const Text('Check readiness'),
              ),
              if (_availability is AppleIntelligenceNotEnabled ||
                  _availability is ModelNotReady)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: _openingSettings ? null : _openSettings,
                  child: const Text('Open iOS Settings'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _card(
            title: ModelCatalogue.qwen.name,
            children: widget.store != null
                ? _downloadable()
                : const [
                    Text(
                      'Not available in this version',
                      style: TextStyle(color: SekretBrand.accent),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Selected for the first downloadable option: Q3_K_M, '
                      '2.08 GB. General text chat only; no image understanding '
                      'or Knowledge Base answers.',
                      style: TextStyle(color: SekretBrand.secondary),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Integration is in progress. Downloads and model switching '
                      'are not enabled yet. Device compatibility and performance '
                      'ratings are not confirmed for this app.',
                      style: TextStyle(color: SekretBrand.secondary),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Custom model imports are not supported. Your chats and '
                      'Knowledge Base stay on this device.',
                      style: TextStyle(color: SekretBrand.secondary),
                    ),
                  ],
          ),
        ],
      ),
    ),
  );

  List<Widget> _downloadable() {
    final store = widget.store!;
    final state = store.state;
    final selected = widget.selection?.selected == ModelCatalogue.qwen.id;
    final active = selected && (widget.selection?.hasLocalLease ?? false);
    final busy = _working || (widget.selection?.busy ?? false);
    return [
      const Text(
        'Preview · General text chat only',
        style: TextStyle(color: SekretBrand.accent),
      ),
      const SizedBox(height: 12),
      const Text(
        'No image understanding or Knowledge Base answers. This small model can make mistakes; check important answers.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Answer quality · App assessment pending\nSpeed · Varies with the device and chat length\nStorage · 2.08 GB (Q3_K_M)',
      ),
      const SizedBox(height: 12),
      Text(switch (state.phase) {
        ModelInstallPhase.absent => 'Not downloaded',
        ModelInstallPhase.downloading =>
          'Downloading · ${(100 * state.receivedBytes / store.model.artifact!.bytes).toStringAsFixed(0)}%',
        ModelInstallPhase.verifying => 'Verifying the downloaded file…',
        ModelInstallPhase.installed =>
          active
              ? 'Selected · Installed on this device'
              : 'Installed · Ready to select',
        ModelInstallPhase.removing => 'Removing downloaded files…',
        ModelInstallPhase.failed => state.message ?? 'Installation failed',
      }),
      if (_localSupported != true)
        Text(
          _localSupported == null
              ? 'Checking device support…'
              : 'This preview is limited to the tested iPhone 15 Pro Max. Other devices and simulators are not enabled yet.',
        ),
      if (state.busy)
        CupertinoButton(
          onPressed: store.cancel,
          child: const Text('Cancel download'),
        ),
      if (!state.busy && state.phase != ModelInstallPhase.installed)
        CupertinoButton(
          onPressed: busy || _localSupported != true ? null : _download,
          child: const Text('Download · 2.08 GB'),
        ),
      if (state.phase == ModelInstallPhase.installed &&
          widget.selection != null) ...[
        CupertinoButton(
          onPressed: busy || active || _localSupported != true
              ? null
              : () => _run(
                  () => widget.selection!.select(ModelCatalogue.qwen.id),
                ),
          child: Text(active ? 'Selected' : 'Use Qwen'),
        ),
        if (selected)
          const Text(
            'Select Apple Intelligence before removing Qwen. No model is switched automatically.',
          ),
      ],
      if (!state.busy &&
          (state.phase == ModelInstallPhase.installed ||
              state.phase == ModelInstallPhase.failed))
        CupertinoButton(
          onPressed: busy || selected ? null : _remove,
          child: const Text('Remove downloaded files'),
        ),
      CupertinoButton(
        onPressed: busy ? null : _licenses,
        child: const Text('License and provenance'),
      ),
    ];
  }

  Widget _card({required String title, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SekretBrand.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SekretBrand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}
