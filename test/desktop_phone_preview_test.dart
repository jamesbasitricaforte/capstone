import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_rescue/data/marketplace_repository.dart';
import 'package:project_rescue/main.dart';
import 'package:project_rescue/widgets/desktop_phone_preview.dart';

void main() {
  testWidgets('desktop preview scales to the window and clears the camera', (
    tester,
  ) async {
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: DesktopPhonePreview(
            child: Scaffold(
              body: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('Notch-safe content'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('desktop-phone-preview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('phone-camera-island')), findsOneWidget);

      final previewSize = tester.getSize(
        find.byKey(const ValueKey('desktop-phone-preview')),
      );
      expect(previewSize.width, lessThan(1366));
      expect(previewSize.height, lessThan(768));

      final contentTop = tester.getTopLeft(find.text('Notch-safe content')).dy;
      final cameraBottom = tester
          .getRect(find.byKey(const ValueKey('phone-camera-island')))
          .bottom;
      expect(contentTop, greaterThan(cameraBottom));
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
      final largerPreviewSize = tester.getSize(
        find.byKey(const ValueKey('desktop-phone-preview')),
      );
      expect(largerPreviewSize.width, greaterThan(previewSize.width));
      expect(largerPreviewSize.height, greaterThan(previewSize.height));
      expect(largerPreviewSize.width, lessThan(1920));
      expect(largerPreviewSize.height, lessThan(1080));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
    }
  });

  testWidgets('phone preview stays off on mobile targets', (tester) async {
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: DesktopPhonePreview(child: Text('Mobile screen')),
        ),
      );

      expect(find.byKey(const ValueKey('desktop-phone-preview')), findsNothing);
      expect(find.byKey(const ValueKey('phone-camera-island')), findsNothing);
      expect(find.text('Mobile screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
    }
  });

  testWidgets('marketplace uses the phone preview on desktop', (tester) async {
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MyApp(repository: InMemoryMarketplaceRepository()),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('desktop-phone-preview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('phone-camera-island')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('I already have an account'));
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Local Produce'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
    }
  });
}
