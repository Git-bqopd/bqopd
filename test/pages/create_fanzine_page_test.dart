import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bqopd/pages/create_fanzine_page.dart'; // Adjust import path as needed
import 'package:bqopd/components/button.dart'; // Adjust import path
import 'package:bqopd/components/textfield.dart'; // Adjust import path

// Mock NavigatorObserver to track navigation events
class MockNavigatorObserver extends NavigatorObserver {
  static final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // Ensure bindings are initialized

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
      // If CreateFanzinePage or its children use Navigator directly or indirectly (e.g. for SnackBars)
      // you might need a navigatorKey or to wrap with a Navigator.
      // For basic widget presence tests, MaterialApp is often sufficient.
      navigatorObservers: [MockNavigatorObserver()],
    );
  }

  group('CreateFanzinePage Widget Tests', () {
    setUp(() {
      MockNavigatorObserver.pushedRoutes.clear();
    });

    testWidgets('UI elements are present', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(const CreateFanzinePage()));

      // Verify AppBar title
      expect(find.text('Create New Fanzine'), findsOneWidget);

      // Verify "Select Fanzine Pages (Images)" button
      // Using text on ElevatedButton is tricky, let's find by Icon or a more specific text
      expect(find.widgetWithText(ElevatedButton, 'Select Fanzine Pages (Images)'), findsOneWidget);
      expect(find.byIcon(Icons.image_search), findsOneWidget);


      // Verify "Title" TextField by associated Text label
      // We added "Title" and "Description" Text widgets above MyTextField
      expect(find.text('Title'), findsOneWidget);
      expect(find.widgetWithText(MyTextField, 'Enter fanzine title'), findsOneWidget);


      // Verify "Description" TextField by associated Text label
      expect(find.text('Description'), findsOneWidget);
      expect(find.widgetWithText(MyTextField, 'Enter fanzine description (optional)'), findsOneWidget);


      // Verify "Create Fanzine" button (MyButton text is "Create Fanzine" after upload logic was added)
      expect(find.widgetWithText(MyButton, 'Create Fanzine'), findsOneWidget);
    });

    testWidgets('"Create Fanzine" button is initially disabled', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(const CreateFanzinePage()));

      final MyButton createButton = tester.widget(find.widgetWithText(MyButton, 'Create Fanzine'));
      // The MyButton's onTap is null when disabled.
      expect(createButton.onTap, isNull);
    });

    testWidgets('"Create Fanzine" button remains disabled after entering only title', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(const CreateFanzinePage()));

      // Find the Title MyTextField
      final titleTextFieldFinder = find.widgetWithText(MyTextField, 'Enter fanzine title');
      expect(titleTextFieldFinder, findsOneWidget);

      // Enter text into the Title field
      await tester.enterText(titleTextFieldFinder, 'My Awesome Fanzine');
      await tester.pump(); // Rebuild the widget tree

      // Verify button is still disabled (because images are missing)
      final MyButton createButton = tester.widget(find.widgetWithText(MyButton, 'Create Fanzine'));
      expect(createButton.onTap, isNull);
    });
    
    // More complex test: Simulating image selection and then title entry to enable the button.
    // This requires mocking image_picker. For now, we'll skip this due to complexity
    // with platform channels, as per the subtask instructions.
    // A placeholder for what it would look like:
    /*
    testWidgets('"Create Fanzine" button enables after image and title', (WidgetTester tester) async {
      // 1. Setup mock for image_picker
      // MethodChannels.setMockMethodCallHandler(ImagePicker.platform, (MethodCall methodCall) async { ... });
      
      await tester.pumpWidget(createTestableWidget(const CreateFanzinePage()));

      // 2. Simulate tapping the image picker button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Select Fanzine Pages (Images)'));
      await tester.pumpAndSettle(); // Allow time for async operations and rebuilds

      // (Assume mock image_picker successfully "picked" an image and updated state)

      // 3. Enter text into the Title field
      final titleTextFieldFinder = find.widgetWithText(MyTextField, 'Enter fanzine title');
      await tester.enterText(titleTextFieldFinder, 'My Awesome Fanzine with Image');
      await tester.pump();

      // 4. Verify button is enabled
      final MyButton createButton = tester.widget(find.widgetWithText(MyButton, 'Create Fanzine'));
      expect(createButton.onTap, isNotNull);

      // MethodChannels.setMockMethodCallHandler(ImagePicker.platform, null); // Clean up
    });
    */

    // Test for SnackBar when "Create Fanzine" is tapped (even if disabled or fails)
    // This is a bit tricky because the actual upload logic now involves Firebase.
    // If we tap when it's disabled, nothing should happen.
    // If we could enable it (with mocks), it would try to contact Firebase.
    // For a simple widget test without Firebase mocks, we can't easily test the full tap action.
    // However, the button state tests (disabled/enabled) are more valuable at the widget test level here.
  });
}
