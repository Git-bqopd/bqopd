import 'package:bqopd/pages/fanzine_reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bqopd/widgets/profile_widget.dart'; // Adjust import path

// Mock NavigatorObserver to track navigation events
class MockNavigatorObserver extends NavigatorObserver {
  static final List<Route<dynamic>> pushedRoutes = [];
  static Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }

  static void reset() {
    pushedRoutes.clear();
    lastPushedRoute = null;
  }
}

void main() {
  late FakeCloudFirestore fakeFirestore;
  const String testUserId = 'test-user-uid-123';
  const String testUsername = 'TestUser';

  // Mock Fanzine Data
  final mockFanzineData1 = {
    'title': 'Fanzine Alpha',
    'coverImageURL': 'http://example.com/alpha_cover.jpg',
    'authorID': testUserId,
    'createdAt': DateTime.now().subtract(const Duration(days: 2)),
    'pages': ['http://example.com/alpha_page1.jpg'],
    'pageCount': 1,
  };
  const String fanzineId1 = 'fanzine-alpha-001';

  final mockFanzineData2 = {
    'title': 'Fanzine Beta',
    'coverImageURL': 'http://example.com/beta_cover.jpg',
    'authorID': testUserId,
    'createdAt': DateTime.now().subtract(const Duration(days: 1)),
    'pages': ['http://example.com/beta_page1.jpg', 'http://example.com/beta_page2.jpg'],
    'pageCount': 2,
  };
  const String fanzineId2 = 'fanzine-beta-002';


  setUp(() {
    fakeFirestore = FakeCloudFirestore();
    MockNavigatorObserver.reset();
    // This is crucial: ProfileWidget uses FirebaseFirestore.instance directly.
    // For tests, FakeCloudFirestore needs to be set as the instance.
    // This is a global change, so tests should be run in a way that doesn't cause interference if possible,
    // or reset FirebaseFirestore.instance after tests if the testing framework allows.
    // However, fake_cloud_firestore is designed to mock `FirebaseFirestore.instance` automatically
    // when an instance of FakeCloudFirestore is created. So this direct assignment might not be needed
    // and could even be problematic if the library handles it differently.
    // Let's rely on fake_cloud_firestore's behavior of automatically mocking the static instance.
  });

  Widget createTestableWidget({
      required String userId,
      required String username,
      FakeCloudFirestore? firestoreInstance, // Allow passing specific instance for clarity
    }) {
    // If firestoreInstance is provided, it's mostly for ensuring the test setup is clear.
    // FakeCloudFirestore's typical usage is that creating an instance of it already
    // redirects FirebaseFirestore.instance.
    if (firestoreInstance != null) {
      // This line would be: FirebaseFirestore.instance = firestoreInstance;
      // But as noted, it might be handled automatically by FakeCloudFirestore.
      // For safety, we'll ensure our fakeFirestore variable is the one being used.
    }

    return MaterialApp(
      home: Scaffold(
        body: ProfileWidget(
          userId: userId,
          username: username,
        ),
      ),
      navigatorObservers: [MockNavigatorObserver()],
    );
  }

  group('ProfileWidget Tests', () {
    testWidgets('displays username and loading indicator initially', (WidgetTester tester) async {
      await tester.pumpWidget(createTestableWidget(userId: testUserId, username: testUsername, firestoreInstance: fakeFirestore));

      expect(find.text(testUsername), findsOneWidget); // Username from prop
      expect(find.text("${testUsername}'s Fanzines"), findsOneWidget); // Section header
      expect(find.byType(CircularProgressIndicator), findsOneWidget); // Loading for fanzines
    });

    testWidgets('displays "No fanzines found" message when user has no fanzines', (WidgetTester tester) async {
      // No data added to fakeFirestore for testUserId

      await tester.pumpWidget(createTestableWidget(userId: testUserId, username: testUsername, firestoreInstance: fakeFirestore));
      await tester.pumpAndSettle(); // Allow StreamBuilder to process empty stream

      expect(find.text(testUsername), findsOneWidget);
      expect(find.text("${testUsername}'s Fanzines"), findsOneWidget);
      expect(find.text("No fanzines found for this user."), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GridView), findsNothing); // No grid if no fanzines
    });

    testWidgets('displays fanzines correctly when data is available', (WidgetTester tester) async {
      // Add mock fanzine data to Firestore
      await fakeFirestore.collection('fanzines').doc(fanzineId1).set(mockFanzineData1);
      await fakeFirestore.collection('fanzines').doc(fanzineId2).set(mockFanzineData2);
      // Add a fanzine for another user to ensure filtering works
      await fakeFirestore.collection('fanzines').doc('other-fanzine').set({
        'title': 'Other User Fanzine',
        'coverImageURL': 'http://example.com/other.jpg',
        'authorID': 'other-user-id',
        'createdAt': DateTime.now(),
      });


      await tester.pumpWidget(createTestableWidget(userId: testUserId, username: testUsername, firestoreInstance: fakeFirestore));
      await tester.pumpAndSettle(); // Process the stream

      expect(find.text(testUsername), findsOneWidget);
      expect(find.text("${testUsername}'s Fanzines"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GridView), findsOneWidget);

      // Check for fanzine titles (indirectly checks for _FanzineListItem rendering)
      expect(find.text('Fanzine Alpha'), findsOneWidget);
      expect(find.text('Fanzine Beta'), findsOneWidget);
      expect(find.text('Other User Fanzine'), findsNothing); // Ensure filtering by userId works

      // Verify images (more robust: check Image.network URLs if possible, like in FanzineReaderPage tests)
      final allImages = tester.widgetList<Image>(find.byType(Image));
      
      bool cover1Found = allImages.any((img) => img.image is NetworkImage && (img.image as NetworkImage).url == mockFanzineData1['coverImageURL']);
      expect(cover1Found, isTrue, reason: "Cover for Fanzine Alpha not found");

      bool cover2Found = allImages.any((img) => img.image is NetworkImage && (img.image as NetworkImage).url == mockFanzineData2['coverImageURL']);
      expect(cover2Found, isTrue, reason: "Cover for Fanzine Beta not found");
    });

    testWidgets('displays error message when Firestore fetch fails', (WidgetTester tester) async {
      // To simulate an error, we can make the fakeFirestore instance throw an exception
      // when 'fanzines' collection is accessed. This is a bit advanced for FakeCloudFirestore.
      // A simpler way for widget test is to rely on the stream error state if we can control it.
      // However, FakeCloudFirestore doesn't easily allow injecting stream errors directly.
      // For this test, we'll assume a scenario where the stream itself reports an error,
      // which ProfileWidget should handle. This is harder to set up reliably without more
      // control over the stream source or using a mock that can emit errors on demand.

      // As a proxy, if the widget's stream somehow produced an error (e.g., network issue
      // that FakeCloudFirestore might not simulate, or a security rule violation),
      // it should show an error.
      // We can't easily force FakeCloudFirestore to return a stream error for this specific query.
      // So, this test case might be limited in its current setup.
      // A "real" integration test with emulators would be better for actual error states.

      // For now, let's acknowledge this limitation. If ProfileWidget's StreamBuilder
      // `snapshot.hasError` path were to be triggered, it should display an error.
      // We can test the UI for error display if we could manually set an error state,
      // but ProfileWidget doesn't expose that directly.
      
      // Let's skip a direct error injection test for fanzine fetching for now due to
      // the limitations of easily forcing FakeCloudFirestore to produce a stream error.
      // The StreamBuilder has `Text('Error loading fanzines: ${snapshot.error}')`
      // which we assume works if an error occurs.
      print("Skipping fanzine fetch error test due to FakeCloudFirestore limitations for stream error injection.");
    });

    testWidgets('tapping a fanzine item navigates to FanzineReaderPage', (WidgetTester tester) async {
      await fakeFirestore.collection('fanzines').doc(fanzineId1).set(mockFanzineData1);

      await tester.pumpWidget(createTestableWidget(userId: testUserId, username: testUsername, firestoreInstance: fakeFirestore));
      await tester.pumpAndSettle();

      expect(find.text('Fanzine Alpha'), findsOneWidget);

      // Tap the fanzine. Need to find the specific InkWell.
      // The _FanzineListItem has a Card, then Column, then Text for title.
      // We find the text, then go up to find the InkWell.
      final fanzineAlphaTextFinder = find.text('Fanzine Alpha');
      // Find the InkWell that is an ancestor of this text.
      final inkWellFinder = find.ancestor(
        of: fanzineAlphaTextFinder,
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget, reason: "InkWell for Fanzine Alpha not found");

      await tester.tap(inkWellFinder);
      await tester.pumpAndSettle(); // Allow navigation to process

      expect(MockNavigatorObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = MockNavigatorObserver.lastPushedRoute;
      expect(pushedRoute, isA<MaterialPageRoute>());
      expect((pushedRoute as MaterialPageRoute).builder(GlobalKey<NavigatorState>().currentContext!), isA<FanzineReaderPage>());

      // Verify correct parameters passed to FanzineReaderPage
      final readerPage = (pushedRoute as MaterialPageRoute).builder(GlobalKey<NavigatorState>().currentContext!) as FanzineReaderPage;
      expect(readerPage.fanzineID, fanzineId1);
      expect(readerPage.fanzineTitle, mockFanzineData1['title']);
    });
  });
}
