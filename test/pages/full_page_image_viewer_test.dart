import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bqopd/pages/full_page_image_viewer.dart'; // Adjust import path
// Removed: import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
// Removed: import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// Removed: import 'package:share_plus/share_plus.dart';

// Mock NavigatorObserver to track navigation events (can be shared or defined per test file)
class MockNavigatorObserver extends NavigatorObserver {
  static final List<Route<dynamic>> pushedRoutes = [];
  static Route<dynamic>? lastPushedRoute;
  static bool popCalled = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCalled = true;
    super.didPop(route, previousRoute);
  }

  static void reset() {
    pushedRoutes.clear();
    lastPushedRoute = null;
    popCalled = false;
  }
}

void main() {
  const String testImageUrl = 'http://example.com/test_image.jpg';
  // Removed: const String testFanzineTitle = 'My Awesome Zine';
  // Removed: const String testFanzineAuthor = 'Cool Author';

  // Removed: late MockSharePlusPlatform mockSharePlatform;

  setUp(() {
    MockNavigatorObserver.reset();
    // Removed: mockSharePlatform = MockSharePlusPlatform();
    // Removed: SharePlatform.instance = mockSharePlatform;
    // Removed: MockSharePlusPlatform.resetSharedValues();
  });

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
      navigatorObservers: [MockNavigatorObserver()],
    );
  }

  group('FullPageImageViewer Widget Tests', () {
    testWidgets('renders correctly with image and AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(
        const FullPageImageViewer(imageUrl: testImageUrl),
      ));

      // Verify AppBar is present (implicitly, by finding its elements)
      expect(find.byType(AppBar), findsOneWidget);

      // Verify "Close" button in AppBar
      expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);

      // Verify InteractiveViewer is present
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // Verify Image.network is present with the correct imageUrl
      // Find the Image widget and check its properties
      final imageWidget = tester.widget<Image>(find.byType(Image));
      expect(imageWidget.image, isA<NetworkImage>());
      expect((imageWidget.image as NetworkImage).url, testImageUrl);
    });

    testWidgets('Close button in AppBar calls Navigator.pop', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(
        const FullPageImageViewer(imageUrl: testImageUrl),
      ));

      final closeButton = find.widgetWithIcon(IconButton, Icons.close);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle(); // Allow time for navigation

      // Verify Navigator.pop was called
      expect(MockNavigatorObserver.popCalled, isTrue);
    });

    testWidgets('renders placeholder social media icons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(
        const FullPageImageViewer(imageUrl: testImageUrl),
      ));

      // Verify presence of social media icons by their IconData or tooltip
      expect(find.widgetWithIcon(IconButton, Icons.facebook), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.share), findsOneWidget); // Generic share
      expect(find.widgetWithIcon(IconButton, Icons.camera_alt_outlined), findsOneWidget); // Instagram-like
      expect(find.widgetWithIcon(IconButton, Icons.link), findsOneWidget); // Copy link

      // Or by tooltip
      expect(find.byTooltip('Share to Facebook'), findsOneWidget);
      expect(find.byTooltip('Share to Twitter'), findsOneWidget);
      expect(find.byTooltip('Share to Instagram'), findsOneWidget);
      expect(find.byTooltip('Share to Copy Link'), findsOneWidget);
    });

    testWidgets('tapping a social media icon shows a SnackBar', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(
        const FullPageImageViewer(imageUrl: testImageUrl),
      ));

      final facebookIcon = find.widgetWithIcon(IconButton, Icons.facebook);
      expect(facebookIcon, findsOneWidget);

      await tester.tap(facebookIcon);
      await tester.pump(); // SnackBar animation starts
      await tester.pump(); // SnackBar is fully visible

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Share to Facebook tapped (not implemented).'), findsOneWidget);

      // It's good practice to ensure the SnackBar disappears to not affect other tests
      await tester.pump(const Duration(seconds: 3)); // Wait for default SnackBar duration
      await tester.pump(); // Let it rebuild without the SnackBar
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
