export 'web_firebase_interop_stub.dart'
if (dart.library.html) 'web_firebase_interop_web.dart';

/// Statically typed interface representing a cancellable subscription to avoid dynamic dispatch at runtime.
abstract class FirebaseSubscription {
  void callAsFunction();
}