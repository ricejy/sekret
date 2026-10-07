import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/ui/sekret_brand.dart';
import 'package:sekret/ui/settings/onboarding_tuck.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    OnboardingPose pose, {
    bool reduce = false,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: SekretBrand.theme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: CupertinoPageScaffold(child: OnboardingTuck(pose: pose)),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  String asset(WidgetTester tester) {
    final provider =
        tester.widget<Image>(find.byType(Image).last).image as ResizeImage;
    return (provider.imageProvider as AssetImage).assetName;
  }

  testWidgets(
    'each pose animates once on arrival, not on rebuild or readiness updates',
    (tester) async {
      bool moving() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(OnboardingTuck),
              matching: find.byType(Transform),
            ),
          )
          .any(
            (transform) => transform.transform.getTranslation().y.abs() > .1,
          );
      for (final pose in OnboardingPose.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await mount(tester, pose, settle: false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(moving(), isTrue, reason: pose.name);
        await tester.pumpAndSettle();
        expect(moving(), isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await mount(tester, pose, settle: false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(moving(), isFalse);
      }
      await mount(tester, OnboardingPose.ready, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(moving(), isFalse);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('welcome reaction is finite and changes pose on tap', (
    tester,
  ) async {
    await mount(tester, OnboardingPose.welcome);
    expect(asset(tester), 'assets/brand/tuck.png');
    await tester.tap(find.byType(OnboardingTuck));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(asset(tester), 'assets/brand/tuck-ready.png');
    expect(
      find.descendant(
        of: find.byType(OnboardingTuck),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Reduce Motion keeps pose feedback without moving or fading', (
    tester,
  ) async {
    await mount(tester, OnboardingPose.shell, reduce: true);
    expect(asset(tester), 'assets/brand/tuck-shell.png');
    for (final transform in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(OnboardingTuck),
        matching: find.byType(Transform),
      ),
    )) {
      expect(transform.transform.isIdentity(), isTrue);
    }
    await tester.tap(find.byType(OnboardingTuck));
    await tester.pump();
    await tester.pump();
    expect(asset(tester), 'assets/brand/tuck.png');
    expect(
      find.descendant(
        of: find.byType(OnboardingTuck),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      Duration.zero,
    );
    for (final transform in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(OnboardingTuck),
        matching: find.byType(Transform),
      ),
    )) {
      expect(transform.transform.isIdentity(), isTrue);
    }
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'changing readiness clears reactions and uses the matching pose',
    (tester) async {
      await mount(tester, OnboardingPose.curious);
      expect(asset(tester), 'assets/brand/tuck-curious.png');
      await tester.tap(find.byType(OnboardingTuck));
      await tester.pump(const Duration(milliseconds: 100));
      await mount(tester, OnboardingPose.ready);
      expect(asset(tester), 'assets/brand/tuck-ready.png');
      expect(
        find.descendant(
          of: find.byType(OnboardingTuck),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
