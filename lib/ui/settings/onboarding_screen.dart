import 'package:flutter/cupertino.dart';
import '../../core/platform/llm_backend.dart';
import '../../core/settings/app_protection.dart';
import 'settings_screen.dart';
import '../sekret_brand.dart';
import 'onboarding_tuck.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.protection,
    required this.model,
    required this.openSystemSettings,
  });
  final AppProtection protection;
  final LlmBackend model;
  final Future<void> Function() openSystemSettings;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  LlmAvailability? _status;
  int _step = 0;
  bool _checking = false;
  bool _busy = false;
  String? _error;
  bool _preloadedPoses = false;
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_preloadedPoses) return;
    _preloadedPoses = true;
    for (final asset in [
      'tuck.png',
      'tuck-curious.png',
      'tuck-ready.png',
      'tuck-shell.png',
    ]) {
      precacheImage(
        ResizeImage(AssetImage('assets/brand/$asset'), width: 528),
        context,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == 1) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final status = await widget.model.availability();
      if (mounted) setState(() => _status = status);
    } on Object {
      if (mounted) setState(() => _status = const ModelNotReady());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _goTo(int step) {
    if (_busy) return;
    setState(() {
      _step = step;
      _error = null;
    });
    if (step == 1) _check();
  }

  Future<void> _enableAndFinish() => _run(() async {
    if (widget.protection.settings?.biometricLockEnabled != true) {
      final enabled = await widget.protection.setEnabled(true);
      if (!mounted) return;
      if (!enabled) {
        setState(() => _error = widget.protection.error);
        return;
      }
    }
    await widget.protection.finishOnboarding();
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not save this choice. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      border: null,
      leading: _step == 0
          ? null
          : CupertinoNavigationBarBackButton(onPressed: () => _goTo(_step - 1)),
      middle: Text(switch (_step) {
        0 => 'Welcome to Sekret',
        1 => 'Apple Intelligence',
        _ => 'App lock',
      }),
    ),
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Semantics(
                label: 'Step ${_step + 1} of 3',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        for (var step = 0; step < 3; step++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: _reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              height: 3,
                              margin: EdgeInsets.only(right: step == 2 ? 0 : 8),
                              decoration: BoxDecoration(
                                color: step <= _step
                                    ? SekretBrand.accent
                                    : SekretBrand.line,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_step),
                  tween: Tween(begin: 0, end: 1),
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 12),
                      child: child,
                    ),
                  ),
                  child: ListView(
                    key: ValueKey('onboarding-content-$_step'),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    children: _content(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Semantics(liveRegion: true, child: Text(_error!)),
                      const SizedBox(height: 12),
                    ],
                    if (_step == 2 &&
                        widget.protection.settings?.biometricLockEnabled !=
                            true)
                      CupertinoButton(
                        onPressed: _busy
                            ? null
                            : () => _run(widget.protection.finishOnboarding),
                        child: const Text('Skip for now'),
                      ),
                    CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _busy
                          ? null
                          : _step == 2
                          ? _enableAndFinish
                          : () => _goTo(_step + 1),
                      child: Text(switch (_step) {
                        0 => 'Continue',
                        1 =>
                          _status is Available
                              ? 'Continue'
                              : 'Continue without AI',
                        _ =>
                          widget.protection.settings?.biometricLockEnabled ==
                                  true
                              ? 'Continue to Sekret'
                              : 'Enable app lock',
                      }, textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> _content() => switch (_step) {
    0 => [
      const OnboardingTuck(pose: OnboardingPose.welcome),
      const SizedBox(height: 20),
      const Text(
        'Your chats\nYour data\nSafe on this device',
        style: TextStyle(
          fontSize: 30,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.7,
        ),
      ),
      const SizedBox(height: 24),
      for (final text in const [
        'Chat history, AI responses, document processing, and search all stay local.',
        'No account or cloud service is needed.',
        'No big tech stealing your data.',
        'Full control of your own data.',
      ]) ...[
        Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            height: 1.4,
            color: SekretBrand.secondary,
          ),
        ),
        const SizedBox(height: 12),
      ],
    ],
    1 => [
      OnboardingTuck(
        pose: !_checking && _status is Available
            ? OnboardingPose.ready
            : OnboardingPose.curious,
      ),
      const SizedBox(height: 24),
      const Text(
        'Check your on-device AI',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 16),
      const Text(
        'Sekret uses Apple’s on-device model when Apple Intelligence is enabled and ready on a supported device.',
        style: TextStyle(height: 1.4, color: SekretBrand.secondary),
      ),
      const SizedBox(height: 12),
      const Text(
        'A local text model preview is in Models on supported iPhones. Download only if you choose.',
        style: TextStyle(height: 1.4, color: SekretBrand.secondary),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SekretBrand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SekretBrand.line),
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _checking && !_reduceMotion
                    ? const CupertinoActivityIndicator()
                    : Icon(
                        _checking
                            ? CupertinoIcons.ellipsis_circle
                            : _status is Available
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.info_circle,
                        color: SekretBrand.accent,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _checking ? 'Checking on-device AI…' : modelStatus(_status),
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_status is! Available && !_checking) ...[
        const SizedBox(height: 16),
        const Text(
          'You can continue without AI and still browse history, preview and import knowledge where supported, and manage Settings.',
        ),
        CupertinoButton(
          onPressed: _busy ? null : () => _run(widget.openSystemSettings),
          child: const Text('Open iOS Settings'),
        ),
      ],
      CupertinoButton(
        onPressed: _busy || _checking ? null : _check,
        child: const Text('Check readiness'),
      ),
    ],
    _ => [
      const OnboardingTuck(pose: OnboardingPose.shell),
      const SizedBox(height: 24),
      const Text(
        'A little extra protection',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 20),
      const Text(
        'Use Face ID, Touch ID, or your device passcode to open Sekret.',
        style: TextStyle(height: 1.4),
      ),
      const SizedBox(height: 16),
      const Text(
        'App lock is optional. You can change it later in Settings.',
        style: TextStyle(height: 1.4, color: SekretBrand.secondary),
      ),
    ],
  };
}
