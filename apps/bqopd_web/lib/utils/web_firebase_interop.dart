export 'web_firebase_interop_stub.dart'
if (dart.library.html) 'web_firebase_interop_web.dart';

import 'dart:async';

/// Statically typed interface representing a cancellable subscription to avoid dynamic dispatch at runtime.
abstract class FirebaseSubscription {
  void callAsFunction();
}

/// Global stream controller to trigger a floating, centered login modal layer
/// whenever a guest attempts a restricted action across the Jaspr Web application.
class GlobalModalBus {
  static final _controller = StreamController<bool>.broadcast();
  static Stream<bool> get stream => _controller.stream;

  static void show() {
    _controller.add(true);
  }

  static void hide() {
    _controller.add(false);
  }
}