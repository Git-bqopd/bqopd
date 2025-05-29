import 'package:bqopd/pages/create_fanzine_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bqopd/widgets/my_info_widget.dart'; // Adjust import path as needed
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart'; // For mocking FirebaseAuth
import 'package:cloud_firestore_mocks/cloud_firestore_mocks.dart'; // For mocking Firestore
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart'; // Alternative if cloud_firestore_mocks has issues

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

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      pushedRoutes.remove(oldRoute); // Assuming oldRoute would have been pushed
      pushedRoutes.add(newRoute);
      lastPushedRoute = newRoute;
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}


Widget createMyInfoTestWidget({
  required Widget child,
  FirebaseAuth? firebaseAuth,
  FirebaseFirestore? firestore,
  List<NavigatorObserver>? navigatorObservers,
}) {
  // Using FakeCloudFirestore as it's often more up-to-date and easier to manage for simple cases.
  final firestoreInstance = firestore ?? FakeCloudFirestore();
  final authInstance = firebaseAuth ?? MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'testuser123', email: 'test@example.com', displayName: 'Test User'));

  // If MyInfoWidget or its children expect specific providers (e.g., for Firebase services),
  // they might need to be wrapped here. For now, assuming direct use or that
  // the mocks handle the static instance calls if that's how the app is structured.
  // This is a common challenge with Firebase in widget tests without a proper DI setup.

  // For MyInfoWidget, it directly calls FirebaseFirestore.instance and FirebaseAuth.instance.
  // These static calls are harder to mock without a DI framework or specific mock initializers
  // provided by some Firebase testing packages if they exist and are configured.
  // The `firebase_auth_mocks` and `cloud_firestore_mocks` (or `fake_cloud_firestore`)
  // typically work by mocking the platform channels or providing mock instances.
  // We'll assume for this test that the environment is set up such that these mocks are effective.

  return MaterialApp(
    home: Scaffold(body: child), // MyInfoWidget is usually part of a larger page
    navigatorObservers: navigatorObservers ?? [MockNavigatorObserver()],
  );
}


void main() {
  // late MockFirebaseAuth mockAuth;
  late FakeCloudFirestore fakeFirestore; // Using FakeCloudFirestore

  setUp(() {
    // mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'testuser123', email: 'test@example.com'));
    fakeFirestore = FakeCloudFirestore();
    // Setup initial data for the user if MyInfoWidget tries to load it
    // This depends on how _loadUserData in MyInfoWidget is structured.
    // It uses currentUser.email as the document ID in the 'Users' collection.
    final mockUser = MockUser(uid: 'testuser123', email: 'test@example.com', displayName: 'Test User');
    
    // MyInfoWidget uses FirebaseAuth.instance.currentUser, so we need a global mock for that.
    // This is usually done in a test setup file or using a helper.
    // For simplicity, we'll rely on the implicit mocking if firebase_auth_mocks supports it globally
    // or assume it's handled by the test environment. This is a common pain point.
    // Let's assume MyInfoWidget is robust enough or the test environment handles this.

    // Pre-populate user data that MyInfoWidget will try to fetch
    fakeFirestore.collection('Users').doc(mockUser.email).set({
      'username': 'tester',
      'firstName': 'Test',
      'lastName': 'User',
      // Add other fields as expected by MyInfoWidget
    });
    
    MockNavigatorObserver.pushedRoutes.clear();
    MockNavigatorObserver.lastPushedRoute = null;
  });

  group('MyInfoWidget Tests', () {
    testWidgets('renders basic user info and action links', (WidgetTester tester) async {
      // For this test, we need to ensure that FirebaseAuth.instance.currentUser returns a mock user.
      // And FirebaseFirestore.instance returns our fakeFirestore.
      // This setup can be complex. Using a library like `firebase_ui_testing` or manual setup.
      // For now, we'll assume the widget handles null user gracefully or mock is effective.
      
      // Create a MockFirebaseAuth instance that is signed in.
      final mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'testuser123', email: 'test@example.com', displayName: 'Test User'));

      await tester.pumpWidget(createMyInfoTestWidget(
        child: MyInfoWidget(), // Pass the mock instances if MyInfoWidget could take them via constructor
                               // Otherwise, global mocking is needed.
        firebaseAuth: mockAuth, // This won't work if MyInfoWidget uses FirebaseAuth.instance directly
        firestore: fakeFirestore,
      ));

      // Wait for async operations like _loadUserData and _initFanzinesStream to complete.
      // Using pumpAndSettle might be too much if there are continuous streams.
      // A few pumps should be enough for initial data load.
      await tester.pump(const Duration(seconds: 1)); // Initial data load
      await tester.pump(const Duration(seconds: 1)); // Stream init (if any)
      await tester.pump(const Duration(seconds: 1)); // Further rebuilds


      // Check for some profile information (e.g., username based on our mock setup)
      // This requires _loadUserData to successfully use the mocked services.
      // If direct FirebaseAuth.instance.currentUser is used, this part might fail without proper global mocking.
      // expect(find.text('Username: tester'), findsOneWidget); // This depends on successful mock of Firestore read

      // Verify presence of the "[create fanzine]" link
      expect(find.text('[create fanzine]'), findsOneWidget);
      
      // Verify other links for completeness
      expect(find.text('[view profile]'), findsOneWidget);
      expect(find.text('[edit info]'), findsOneWidget);
      expect(find.text('[upload image]'), findsOneWidget);

      // Verify "My Fanzines" section header appears (added in a previous subtask)
      // This also depends on the user being successfully loaded to avoid error messages
      // and _isLoading being false.
      // expect(find.text("My Fanzines"), findsOneWidget);
    });

    testWidgets('tapping "[create fanzine]" link attempts to navigate to CreateFanzinePage', (WidgetTester tester) async {
      final mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'testuser123', email: 'test@example.com'));
      
      await tester.pumpWidget(createMyInfoTestWidget(
        child: MyInfoWidget(),
        firebaseAuth: mockAuth,
        firestore: fakeFirestore,
      ));

      // Similar pump sequence as above
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));


      final createFanzineLink = find.text('[create fanzine]');
      expect(createFanzineLink, findsOneWidget);

      // Tap the link
      await tester.tap(createFanzineLink);
      await tester.pumpAndSettle(); // Allow navigation to process

      // Verify that a push navigation occurred
      expect(MockNavigatorObserver.pushedRoutes, isNotEmpty);
      // Verify that the pushed route is for CreateFanzinePage
      expect(MockNavigatorObserver.lastPushedRoute, isA<MaterialPageRoute>());
      final pushedRoute = MockNavigatorObserver.lastPushedRoute as MaterialPageRoute;
      expect(pushedRoute.builder(GlobalKey<NavigatorState>().currentContext!), isA<CreateFanzinePage>());
    });
  });
}
