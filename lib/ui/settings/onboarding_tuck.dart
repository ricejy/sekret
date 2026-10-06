import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import '../sekret_brand.dart';

enum OnboardingPose { welcome, curious, ready, shell }

/// A finite, optional character interaction. Never changes readiness or security.
class OnboardingTuck extends StatefulWidget {
  const OnboardingTuck({super.key, required this.pose});
  final OnboardingPose pose;

  @override
  State<OnboardingTuck> createState() => _OnboardingTuckState();
}

class _OnboardingTuckState extends State<OnboardingTuck>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final _reaction = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _alternate = false;
  bool _reduceMotion = false;
  bool _playedEntrance = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion) _reaction.reset();
    if (!_playedEntrance) {
      _playedEntrance = true;
      if (!_reduceMotion) _reaction.forward();
    }
  }

  @override
  void didUpdateWidget(OnboardingTuck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pose != widget.pose) {
      _alternate = false;
      // A readiness update is not a new page visit: let the one-shot entrance
      // finish instead of cancelling it or replaying it.
    }
  }

  @override
  void dispose() {
    _reaction.dispose();
    super.dispose();
  }

  void _respond() {
    setState(() => _alternate = !_alternate);
    if (!_reduceMotion) _reaction.forward(from: 0);
  }

  String get _asset => switch (widget.pose) {
    OnboardingPose.welcome => _alternate ? 'tuck-ready.png' : 'tuck.png',
    OnboardingPose.curious => _alternate ? 'tuck.png' : 'tuck-curious.png',
    OnboardingPose.ready => _alternate ? 'tuck.png' : 'tuck-ready.png',
    OnboardingPose.shell => _alternate ? 'tuck.png' : 'tuck-shell.png',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final label = switch (widget.pose) {
      OnboardingPose.welcome => 'Say hello to Tuck',
      OnboardingPose.curious => 'Give Tuck encouragement',
      OnboardingPose.ready => 'Give Tuck a high five',
      OnboardingPose.shell =>
        _alternate
            ? 'Let Tuck tuck into the shell'
            : 'Let Tuck peek out of the shell',
    };
    return Center(
      child: Semantics(
        button: true,
        label: label,
        hint: widget.pose == OnboardingPose.shell
            ? 'Illustration only. Does not enable app lock.'
            : 'Play a short mascot reaction.',
        onTap: _respond,
        child: ExcludeSemantics(
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _respond,
            // Keep the system's default button fade out of Reduce Motion.
            pressedOpacity: 1,
            child: SizedBox(
              width: 224,
              height: 184,
              child: AnimatedBuilder(
                animation: _reaction,
                builder: (context, child) {
                  final wave = math.sin(_reaction.value * math.pi);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 156 + wave * 12,
                        height: 156 + wave * 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              SekretBrand.accent.withValues(alpha: .13),
                              SekretBrand.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, -8 * wave),
                        child: Transform.rotate(
                          angle: math.sin(_reaction.value * math.pi * 2) * .045,
                          child: child,
                        ),
                      ),
                    ],
                  );
                },
                child: AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: Image.asset(
                    'assets/brand/$_asset',
                    key: ValueKey(_asset),
                    width: 176,
                    height: 176,
                    cacheWidth: 528,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
