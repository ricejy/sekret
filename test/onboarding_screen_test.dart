import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekret/core/platform/llm_backend.dart';
import 'package:sekret/core/settings/app_protection.dart';
import 'package:sekret/core/storage/local_data_vault.dart';
import 'package:sekret/ui/settings/onboarding_screen.dart';
import 'package:sekret/ui/sekret_brand.dart';
import 'package:sekret/ui/settings/onboarding_tuck.dart';
import 'app_protection_test.dart' show FakeDeviceProtection;
import 'settings_app_test.dart' show settleSettings;

class _ReadinessModel implements LlmBackend {
  LlmAvailability status = const Available();
  int checks = 0;
  bool fail = false;
  Completer<LlmAvailability>? pending;

  @override
  Future<LlmAvailability> availability() async {
    checks++;
    if (fail) throw StateError('Fixture failure');
    return pending == null ? status : pending!.future;
  }

  @override
  Stream<String> generate({
    required String question,
    required List<String> evidence,
    required String prompt,
  }) => throw StateError('Onboarding must never generate');
}

void main() {
  late LocalDataVault vault;
  late FakeDeviceProtection device;
  late AppProtection protection;
  late _ReadinessModel model;
  var settingsOpened = 0;

  setUp(() async {
    vault = await openLocalDataVault(databasePath: ':memory:');
    device = FakeDeviceProtection();
    protection = AppProtection(vault.settings, device);
    await protection.initialize();
    model = _ReadinessModel();
    settingsOpened = 0;
  });
  tearDown(() async {
    protection.dispose();
    await vault.close();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CupertinoApp(
        theme: SekretBrand.theme,
        home: OnboardingScreen(
          protection: protection,
          model: model,
          openSystemSettings: () async {
            settingsOpened++;
          },
        ),
      ),
    );
    await settleSettings(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    if (find.text(label).hitTestable().evaluate().isEmpty) {
      await tester.scrollUntilVisible(find.text(label), 150);
      await Scrollable.ensureVisible(
        tester.element(find.text(label)),
        alignment: .5,
      );
      await settleSettings(tester);
    }
    await tester.tap(find.text(label));
    await settleSettings(tester);
  }

  testWidgets('welcome has exact copy, defers readiness, and pins Continue', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.text('Your chats\nYour data\nSafe on this device'),
      findsOneWidget,
    );
    expect(find.byType(OnboardingTuck), findsOneWidget);
    for (final text in [
      'Chat history, AI responses, document processing, and search all stay local.',
      'No account or cloud service is needed.',
      'No big tech stealing your data.',
      'Full control of your own data.',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.textContaining('Import permissions'), findsNothing);
    expect(find.text('Check readiness'), findsNothing);
    expect(find.text('Enable app lock'), findsNothing);
    expect(model.checks, 0);
    expect(device.requests, 0);
    final button = find.widgetWithText(CupertinoButton, 'Continue');
    final bottom = tester.getBottomLeft(button).dy;
    expect(
      bottom,
      closeTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 20,
        1,
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(button).dy, bottom);
    expect((await vault.settings.get()).onboardingComplete, isFalse);
  });

  testWidgets('three steps, back navigation, and skip without authentication', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'Continue');
    expect(find.text('Apple Intelligence'), findsOneWidget);
    expect(
      find.text(
        'Sekret uses Apple’s on-device model when Apple Intelligence is enabled and ready on a supported device.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Adding or downloading small open-source models to run locally is not available in this build yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ready · On-device Apple Intelligence'), findsOneWidget);
    expect(model.checks, 1);
    expect(find.text('Skip for now'), findsNothing);
    await tap(tester, 'Continue');
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Check readiness'), findsNothing);
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await settleSettings(tester);
    expect(find.text('Apple Intelligence'), findsOneWidget);
    expect((await vault.settings.get()).onboardingComplete, isFalse);
    await tap(tester, 'Continue');
    await tap(tester, 'Skip for now');
    expect((await vault.settings.get()).onboardingComplete, isTrue);
    expect((await vault.settings.get()).biometricLockEnabled, isFalse);
    expect(device.requests, 0);
  });

  testWidgets('failed lock authentication stays on step three and can retry', (
    tester,
  ) async {
    device.success = false;
    await mount(tester);
    await tap(tester, 'Continue');
    await tap(tester, 'Continue');
    await tap(tester, 'Enable app lock');
    expect(
      find.textContaining('Authentication was not completed'),
      findsOneWidget,
    );
    expect((await vault.settings.get()).onboardingComplete, isFalse);
    expect((await vault.settings.get()).biometricLockEnabled, isFalse);
    device.success = true;
    await tap(tester, 'Enable app lock');
    expect(device.requests, 2);
    expect((await vault.settings.get()).onboardingComplete, isTrue);
    expect((await vault.settings.get()).biometricLockEnabled, isTrue);
  });

  testWidgets(
    'playing with Tuck does not check AI, authenticate, or finish onboarding',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byType(OnboardingTuck));
      await settleSettings(tester);
      expect(model.checks, 0);
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await tester.tap(find.byType(OnboardingTuck));
      await settleSettings(tester);
      expect(device.requests, 0);
      final settings = await vault.settings.get();
      expect(settings.biometricLockEnabled, isFalse);
      expect(settings.onboardingComplete, isFalse);
      expect(
        find.descendant(
          of: find.byType(OnboardingTuck),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('in-flight authentication cannot skip or launch twice', (
    tester,
  ) async {
    device.pending = Completer<bool>();
    await mount(tester);
    await tap(tester, 'Continue');
    await tap(tester, 'Continue');
    await tap(tester, 'Enable app lock');
    await tap(tester, 'Enable app lock');
    await tap(tester, 'Skip for now');
    expect(device.requests, 1);
    expect((await vault.settings.get()).onboardingComplete, isFalse);
    device.pending!.complete(false);
    await settleSettings(tester);
    await tap(tester, 'Skip for now');
    expect((await vault.settings.get()).onboardingComplete, isTrue);
    expect((await vault.settings.get()).biometricLockEnabled, isFalse);
  });

  testWidgets(
    'readiness failure supports settings, retry, and continue without AI',
    (tester) async {
      model.fail = true;
      await mount(tester);
      await tap(tester, 'Continue');
      expect(find.textContaining('Model assets are not ready'), findsOneWidget);
      await tap(tester, 'Open iOS Settings');
      expect(settingsOpened, 1);
      model.fail = false;
      model.status = const AppleIntelligenceNotEnabled();
      await tap(tester, 'Check readiness');
      expect(
        find.textContaining('Apple Intelligence is turned off'),
        findsOneWidget,
      );
      await tap(tester, 'Continue without AI');
      expect(find.text('App lock'), findsOneWidget);
      await tap(tester, 'Skip for now');
      expect((await vault.settings.get()).onboardingComplete, isTrue);
    },
  );

  testWidgets('checking and unavailable AI never display the ready pose', (
    tester,
  ) async {
    await mount(tester);
    model.pending = Completer<LlmAvailability>();
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<OnboardingTuck>(find.byType(OnboardingTuck)).pose,
      OnboardingPose.curious,
    );
    expect(find.text('Checking on-device AI…'), findsOneWidget);
    model.pending!.complete(const DeviceNotEligible());
    await settleSettings(tester);
    expect(
      tester.widget<OnboardingTuck>(find.byType(OnboardingTuck)).pose,
      OnboardingPose.curious,
    );
    expect(find.text('Continue without AI'), findsOneWidget);
    model.pending = null;
    model.status = const Available();
    await tap(tester, 'Check readiness');
    await tester.scrollUntilVisible(find.byType(OnboardingTuck), -150);
    expect(
      tester.widget<OnboardingTuck>(find.byType(OnboardingTuck)).pose,
      OnboardingPose.ready,
    );
  });
}
