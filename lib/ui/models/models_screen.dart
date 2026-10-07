import 'package:flutter/cupertino.dart';

import '../../core/models/model_catalogue.dart';
import '../../core/platform/llm_backend.dart';
import '../sekret_brand.dart';
import '../settings/settings_screen.dart' show modelStatus;

/// Reports installed capabilities only; no download or compatibility is implied.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({
    super.key,
    required this.model,
    required this.openSystemSettings,
  });

  final LlmBackend model;
  final Future<void> Function() openSystemSettings;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ModelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
          const Text(
            'Sekret currently uses Apple Foundation Models for generation.',
            style: TextStyle(color: SekretBrand.secondary),
          ),
          const SizedBox(height: 24),
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
            children: const [
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
