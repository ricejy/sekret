import 'package:flutter/cupertino.dart';
import '../sekret_brand.dart';
import '../../core/chat/chat_workspace.dart';
import '../../core/platform/llm_backend.dart';
import '../../core/settings/app_protection.dart';
import '../../core/storage/local_data_vault.dart';

enum LocalDataAction { chats, knowledge, everything }

String modelStatus(LlmAvailability? status) => switch (status) {
  Available() => 'Ready · On-device Apple Intelligence',
  AppleIntelligenceNotEnabled() =>
    'Apple Intelligence is turned off. Enable it in iOS Settings → Apple Intelligence & Siri.',
  ModelNotReady() =>
    'Model assets are not ready. Check Apple Intelligence in iOS Settings and allow its setup to finish.',
  DeviceNotEligible() =>
    'This device or OS does not support the required on-device model.',
  _ => 'Checking on-device model…',
};

String retentionLabel(RetentionPolicy policy) => switch (policy) {
  RetentionPolicy.manual => 'Until I delete them',
  RetentionPolicy.thirtyDays => '30 days after last activity',
  RetentionPolicy.ninetyDays => '90 days after last activity',
};

String shortRetentionLabel(RetentionPolicy policy) => switch (policy) {
  RetentionPolicy.manual => 'Forever',
  RetentionPolicy.thirtyDays => '30 Days',
  RetentionPolicy.ninetyDays => '90 Days',
};

String lockDelayLabel(AppLockDelay delay) => switch (delay) {
  AppLockDelay.immediate => 'Immediately',
  AppLockDelay.oneMinute => 'After 1 minute',
  AppLockDelay.fifteenMinutes => 'After 15 minutes',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.vault,
    required this.workspace,
    required this.protection,
    required this.deleteData,
  });
  final LocalDataVault vault;
  final ChatWorkspace workspace;
  final AppProtection protection;
  final Future<void> Function(LocalDataAction) deleteData;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  VaultSettingsRecord? _settings;
  StorageUsage? _usage;
  Map<String, String> _diagnostics = const {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final settings = await widget.vault.settings.get();
      final usage = await widget.vault.storageUsage();
      final diagnostics = await widget.protection.device.diagnostics();
      if (mounted) {
        setState(() {
          _settings = settings;
          _usage = usage;
          _diagnostics = diagnostics;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not read Settings. Try again.');
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) await _refresh();
    } on Object {
      if (mounted) {
        await _report(
          widget.protection.error ??
              'The change could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _report(String message) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('Not completed'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<T?> _choose<T>(
    String title,
    Iterable<T> values,
    String Function(T) label,
  ) => showCupertinoModalPopup<T>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(title),
      actions: [
        for (final value in values)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, value),
            child: Text(label(value)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ),
  );

  Future<void> _retention() => _run(() async {
    final policy = await _choose(
      'Keep chats',
      RetentionPolicy.values,
      retentionLabel,
    );
    if (policy == null || !mounted) return;
    final preview = await widget.workspace.previewRetention(policy);
    if (!mounted) return;
    if (await _confirm(
      'Change chat retention?',
      '${preview.affectedChats} chats will be permanently deleted now. ${retentionLabel(policy)}. Future cleanup runs when Sekret opens or resumes. Full chats are removed, not summarized.',
      'Apply',
    )) {
      await widget.workspace.confirmRetention(preview);
    }
  });

  Future<void> _delete(LocalDataAction action) => _run(() async {
    final (title, detail) = switch (action) {
      LocalDataAction.chats => (
        'Delete all chats?',
        'All chats, summaries, drafts, and saved source selections will be permanently removed. Your Knowledge Vault stays.',
      ),
      LocalDataAction.knowledge => (
        'Delete entire Knowledge Vault?',
        'All source originals, extracted text, indexes, and processing work will be permanently removed. Chats may retain sensitive information derived from these sources. Their citations will show Source deleted.',
      ),
      LocalDataAction.everything => (
        'Erase all local data?',
        'Permanently delete all chats, summaries, drafts, sources, indexes, processing files and downloaded models. Apple Intelligence will be selected. App-lock and retention settings stay. Requires device authentication.',
      ),
    };
    if (!await _confirm(
          title,
          detail,
          action == LocalDataAction.everything ? 'Erase All' : 'Delete',
        ) ||
        !mounted) {
      return;
    }
    // Authorization is performed in the app-owned operation, not in this view.
    await widget.deleteData(action);
  });

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final usage = _usage;
    final lockOn = settings?.biometricLockEnabled ?? false;
    final authentication = _diagnostics['authentication'];
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        child: ListView(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CupertinoColors.systemRed),
                ),
              ),
            _section(
              header: 'Chats & Storage',
              footer: 'Sizes exclude system caches.',
              children: [
                _tile(
                  icon: CupertinoIcons.clock,
                  color: CupertinoColors.systemIndigo,
                  title: 'Keep Chats',
                  value: settings == null
                      ? null
                      : shortRetentionLabel(settings.retentionPolicy),
                  onTap: _retention,
                ),
                _tile(
                  icon: CupertinoIcons.chat_bubble_2,
                  color: CupertinoColors.systemGreen,
                  title: 'Chats',
                  value: usage == null ? '…' : _bytes(usage.chatBytes),
                ),
                _tile(
                  iconWidget: const VaultIcon(),
                  color: SekretBrand.accentDeep,
                  title: 'Knowledge Vault',
                  value: usage == null
                      ? '…'
                      : _bytes(
                          usage.knowledgeSourceBytes +
                              usage.knowledgeIndexBytes,
                        ),
                ),
              ],
            ),
            _section(
              footer:
                  'Erase All Data also removes downloaded models and needs Face ID, Touch ID or your passcode.',
              children: [
                _action(
                  'Delete All Chats',
                  () => _delete(LocalDataAction.chats),
                ),
                _action(
                  'Delete Knowledge Vault',
                  () => _delete(LocalDataAction.knowledge),
                ),
                _action(
                  'Erase All Data',
                  () => _delete(LocalDataAction.everything),
                ),
              ],
            ),
            _section(
              header: 'App Lock',
              footer:
                  authentication == null ||
                      authentication.startsWith('Unavailable')
                  ? (authentication ?? 'Device authentication is unavailable.')
                  : 'Uses $authentication. Sekret always locks when it starts.',
              children: [
                _tile(
                  icon: CupertinoIcons.lock_fill,
                  color: CupertinoColors.systemBlue,
                  title: 'App Lock',
                  trailing: CupertinoSwitch(
                    value: lockOn,
                    onChanged: _busy || settings == null
                        ? null
                        : (value) => _run(() async {
                            if (!await widget.protection.setEnabled(value)) {
                              if (mounted) {
                                await _report(widget.protection.error!);
                              }
                            }
                          }),
                  ),
                ),
                if (lockOn)
                  _tile(
                    icon: CupertinoIcons.timer,
                    color: CupertinoColors.systemOrange,
                    title: 'Lock After Leaving',
                    value: lockDelayLabel(settings!.lockDelay),
                    onTap: () => _run(() async {
                      final delay = await _choose(
                        'Lock after leaving Sekret',
                        AppLockDelay.values,
                        lockDelayLabel,
                      );
                      if (delay != null) {
                        await widget.protection.setDelay(delay);
                      }
                    }),
                  ),
              ],
            ),
            _section(
              header: 'Privacy',
              children: [
                _fact(
                  CupertinoIcons.device_phone_portrait,
                  CupertinoColors.systemTeal,
                  'Stays on this iPhone',
                  'No account, cloud model or sync.',
                ),
                _fact(
                  CupertinoIcons.arrow_down_circle_fill,
                  CupertinoColors.systemPurple,
                  'Downloads only when you ask',
                  'Hugging Face sees your IP address, never your chats or vault.',
                ),
                _fact(
                  CupertinoIcons.eye_slash_fill,
                  CupertinoColors.systemGrey,
                  'Hidden in the app switcher',
                  'App Lock guards entry; iOS file protection secures stored data.',
                ),
              ],
            ),
            _section(
              header: 'About Sekret',
              footer: 'No analytics. Nothing is collected or sent.',
              children: [
                _tile(
                  icon: CupertinoIcons.info,
                  color: CupertinoColors.systemGrey,
                  title: 'Version',
                  value:
                      '${_diagnostics['version'] ?? '—'} (${_diagnostics['build'] ?? '—'})',
                ),
                _tile(
                  icon: CupertinoIcons.device_phone_portrait,
                  color: CupertinoColors.systemGrey,
                  title: 'System',
                  value: _diagnostics['os'] ?? '—',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                children: [
                  const TuckMascot(size: 64),
                  const SizedBox(height: 4),
                  Text(
                    'Sekret · private by design',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    String? header,
    String? footer,
    required List<Widget> children,
  }) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoListSection.insetGrouped(
      backgroundColor: SekretBrand.background,
      decoration: BoxDecoration(
        color: SekretBrand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      separatorColor: SekretBrand.line,
      header: header == null
          ? null
          : Semantics(
              header: true,
              child: Text(
                header.toUpperCase(),
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
      footer: footer == null
          ? null
          : Text(footer, style: TextStyle(fontSize: 13, color: secondary)),
      children: children,
    );
  }

  /// iOS Settings-style coloured icon badge.
  Widget _badge(Color color, {IconData? icon, Widget? child}) => Container(
    width: 29,
    height: 29,
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(color, context),
      borderRadius: BorderRadius.circular(7),
    ),
    child: IconTheme(
      data: const IconThemeData(color: CupertinoColors.white, size: 18),
      child: Center(child: child ?? Icon(icon)),
    ),
  );

  Widget _tile({
    IconData? icon,
    Widget? iconWidget,
    required Color color,
    required String title,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) => CupertinoListTile(
    leading: _badge(color, icon: icon, child: iconWidget),
    // Title and value share a line when they fit; large type wraps the value.
    title: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        children: [
          Text(title),
          if (value != null)
            Text(
              value,
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
        ],
      ),
    ),
    trailing:
        trailing ?? (onTap == null ? null : const CupertinoListTileChevron()),
    onTap: onTap == null || _busy ? null : onTap,
  );

  Widget _action(String title, VoidCallback onTap) => CupertinoListTile(
    title: Text(
      title,
      style: const TextStyle(color: CupertinoColors.systemRed),
    ),
    onTap: _busy ? null : onTap,
  );

  /// Multi-line, non-interactive statement row.
  Widget _fact(IconData icon, Color color, String title, String detail) =>
      MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 16, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(color, icon: icon),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  String _bytes(int value) => value < 1024
      ? '$value B'
      : value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(1)} KB'
      : '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}
