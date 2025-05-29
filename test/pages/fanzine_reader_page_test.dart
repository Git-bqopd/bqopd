import 'package:bqopd/pages/full_page_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bqopd/pages/fanzine_reader_page.dart'; // Adjust import path as needed

// Mock NavigatorObserver to track navigation events
class MockNavigatorObserver extends NavigatorObserver {
  static final List<Route<dynamic>> pushedRoutes = [];
  static Route<dynamic>? lastPushedRoute;
  static Route<dynamic>? lastPoppedRoute;


  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPoppedRoute = route;
    super.didPop(route, previousRoute);
  }

  static void reset() {
    pushedRoutes.clear();
    lastPushedRoute = null;
    lastPoppedRoute = null;
  }
}

void main() {
  late FakeCloudFirestore fakeFirestore;
  const String testFanzineId = 'test-fanzine-123';
  const String testFanzineTitle = 'My Awesome Test Fanzine';
  const String testCoverImageUrl = 'http://example.com/cover.jpg';
  final List<String> testPageImageUrls = [
    'http://example.com/page1.jpg',
    'http://example.com/page2.jpg',
  ];

  setUp(() {
    fakeFirestore = FakeCloudFirestore();
    MockNavigatorObserver.reset();
  });

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
      navigatorObservers: [MockNavigatorObserver()],
    );
  }

  // Helper to pump widget with FanzineReaderPage
  Future<void> pumpFanzineReaderPage(WidgetTester tester) async {
    await tester.pumpWidget(createTestableWidget(
      FanzineReaderPage(
        fanzineID: testFanzineId,
        fanzineTitle: testFanzineTitle,
        // Note: FanzineReaderPage fetches its own data using FirebaseFirestore.instance
        // So, we need to ensure the fakeFirestore instance is used by the widget.
        // This is typically done by setting FirebaseFirestore.instance = fakeFirestore;
        // but that's global state. For more isolated tests, dependency injection is better.
        // Assuming for now this test environment allows for `FirebaseFirestore.instance` to be
        // implicitly or explicitly pointed to `fakeFirestore` before the widget is pumped.
        // This is a common challenge in Flutter widget testing with Firebase.
        // For FakeCloudFirestore, it often works by just creating an instance.
      ),
    ));
  }


  group('FanzineReaderPage Widget Tests', () {
    testWidgets('shows AppBar title and loading indicator initially', (WidgetTester tester) async {
      // Don't set up data in Firestore yet to keep it in loading state
      await pumpFanzineReaderPage(tester);

      expect(find.text(testFanzineTitle), findsOneWidget); // AppBar title
      expect(find.byType(CircularProgressIndicator), findsOneWidget); // Loading indicator
    });

    testWidgets('shows error message if fanzine not found', (WidgetTester tester) async {
      // Firestore is empty, so it won't find the fanzine
      await pumpFanzineReaderPage(tester);
      await tester.pumpAndSettle(); // Let it try to load and fail

      expect(find.text('Fanzine not found.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('displays fanzine content after loading', (WidgetTester tester) async {
      // Setup mock data in FakeCloudFirestore
      await fakeFirestore.collection('fanzines').doc(testFanzineId).set({
        'title': testFanzineTitle, // Title in doc, though AppBar uses passed title
        'coverImageURL': testCoverImageUrl,
        'pages': testPageImageUrls,
        'authorID': 'testAuthor',
        // Add other fields as expected by the Fanzine data model if any
      });

      await pumpFanzineReaderPage(tester);
      await tester.pumpAndSettle(); // Let it load the data

      // Verify content
      expect(find.text('Author Details / Info Widget (Placeholder)'), findsOneWidget);

      // Verify cover image (by checking for Image.network with the specific URL)
      // We need to find Image.network widgets and check their url property.
      // This is a bit more involved. A simpler check is to find by tooltip or a semantic label if added.
      // For now, let's assume we can find them if they are rendered.
      // The actual image loading won't happen in test.
      final allImages = tester.widgetList<Image>(find.byType(Image));
      bool coverFound = false;
      for (final imageWidget in allImages) {
        if (imageWidget.image is NetworkImage && (imageWidget.image as NetworkImage).url == testCoverImageUrl) {
          coverFound = true;
          break;
        }
      }
      expect(coverFound, isTrue, reason: "Cover image not found with URL $testCoverImageUrl");


      // Verify page images
      for (final pageUrl in testPageImageUrls) {
         bool pageFound = false;
        for (final imageWidget in allImages) {
          if (imageWidget.image is NetworkImage && (imageWidget.image as NetworkImage).url == pageUrl) {
            pageFound = true;
            break;
          }
        }
        expect(pageFound, isTrue, reason: "Page image not found with URL $pageUrl");
      }

      // Check that GridView is present
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('tapping cover image attempts to navigate to FullPageImageViewer', (WidgetTester tester) async {
      await fakeFirestore.collection('fanzines').doc(testFanzineId).set({
        'coverImageURL': testCoverImageUrl,
        'pages': testPageImageUrls,
      });

      await pumpFanzineReaderPage(tester);
      await tester.pumpAndSettle();

      // Find the cover image. This is tricky. We need a way to identify it.
      // Assuming the cover image is the first actual image after the placeholder.
      // The grid items are: Placeholder, Cover, Page1, Page2 ...
      // So, the InkWell for the cover image would be the one wrapping the Image.network for coverImageUrl.

      // Find all InkWell widgets
      final inkWellFinders = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      
      // Try to find the InkWell associated with the cover image.
      // This relies on the structure of the GridView items.
      // The first InkWell after the placeholder (which is not an InkWell)
      // should be the cover image.
      // The author placeholder is not an InkWell.
      // The cover image is the first one that is.

      bool coverTapped = false;
      for(final finder in inkWellFinders) {
        final InkWell inkWell = tester.widget(finder);
        // Attempt to find an Image widget as a child of this InkWell
        final imageFinder = find.descendant(of: finder, matching: find.byType(Image));
        if (imageFinder.evaluate().isNotEmpty) {
          final Image imageWidget = tester.widget(imageFinder.first);
          if (imageWidget.image is NetworkImage && (imageWidget.image as NetworkImage).url == testCoverImageUrl) {
            await tester.tap(finder);
            coverTapped = true;
            break;
          }
        }
      }
      expect(coverTapped, isTrue, reason: "Could not find and tap the cover image InkWell.");
      
      await tester.pumpAndSettle();

      expect(MockNavigatorObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = MockNavigatorObserver.lastPushedRoute;
      expect(pushedRoute, isA<MaterialPageRoute>());
      expect((pushedRoute as MaterialPageRoute).builder(GlobalKey<NavigatorState>().currentContext!), isA<FullPageImageViewer>());
      
      // Also check if the correct imageUrl was passed
      final fullPageViewer = (pushedRoute as MaterialPageRoute).builder(GlobalKey<NavigatorState>().currentContext!) as FullPageImageViewer;
      expect(fullPageViewer.imageUrl, testCoverImageUrl);
    });
  });
}
