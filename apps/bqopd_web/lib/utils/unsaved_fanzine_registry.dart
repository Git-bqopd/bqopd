import 'dart:async';
import 'package:bqopd_core/bqopd_core.dart';

/// Central client-side registry to hold newly created fanzines in a temporary,
/// unsaved state prior to first commitment (Save Configuration).
class UnsavedFanzineRegistry {
  static final Map<String, Fanzine> fanzines = {};
  static final Map<String, List<FanzinePage>> pages = {};
  static final Map<String, StreamController<Fanzine>> fanzineControllers = {};
  static final Map<String, StreamController<List<FanzinePage>>> pagesControllers = {};

  /// Checks if an in-memory temporary fanzine holds the given shortcode.
  static bool hasCode(String code) {
    final codeUpper = code.toUpperCase();
    return fanzines.values.any((fz) => fz.shortCode?.toUpperCase() == codeUpper);
  }

  /// Retrieves a temporary fanzine from its shortcode.
  static Fanzine? getByCode(String code) {
    final codeUpper = code.toUpperCase();
    for (var fz in fanzines.values) {
      if (fz.shortCode?.toUpperCase() == codeUpper) return fz;
    }
    return null;
  }

  /// Adds a new fanzine and pages list into memory.
  static void add(Fanzine fz, List<FanzinePage> pgs) {
    fanzines[fz.id] = fz;
    pages[fz.id] = List<FanzinePage>.from(pgs);
    fanzineControllers[fz.id]?.add(fz);
    pagesControllers[fz.id]?.add(pages[fz.id]!);
  }

  /// Removes a fanzine and purges associated broadcast streams.
  static void remove(String fanzineId) {
    fanzines.remove(fanzineId);
    pages.remove(fanzineId);
    fanzineControllers[fanzineId]?.close();
    fanzineControllers.remove(fanzineId);
    pagesControllers[fanzineId]?.close();
    pagesControllers.remove(fanzineId);
  }

  /// Broadcast controller for fanzine metadata updates.
  static StreamController<Fanzine> getOrCreateFanzineController(String fanzineId) {
    return fanzineControllers.putIfAbsent(fanzineId, () {
      final controller = StreamController<Fanzine>.broadcast();
      scheduleMicrotask(() {
        if (fanzines.containsKey(fanzineId) && !controller.isClosed) {
          controller.add(fanzines[fanzineId]!);
        }
      });
      return controller;
    });
  }

  /// Broadcast controller for page list updates.
  static StreamController<List<FanzinePage>> getOrCreatePagesController(String fanzineId) {
    return pagesControllers.putIfAbsent(fanzineId, () {
      final controller = StreamController<List<FanzinePage>>.broadcast();
      scheduleMicrotask(() {
        if (pages.containsKey(fanzineId) && !controller.isClosed) {
          controller.add(pages[fanzineId]!);
        }
      });
      return controller;
    });
  }

  /// High-performance stream that emits the current fanzine state immediately upon listening
  /// and forwards all subsequent updates from the broadcast stream.
  static Stream<Fanzine> watchFanzine(String fanzineId) {
    final controller = StreamController<Fanzine>.broadcast();
    StreamSubscription<Fanzine>? sub;
    controller.onListen = () {
      if (fanzines.containsKey(fanzineId)) {
        controller.add(fanzines[fanzineId]!);
      }
      sub = getOrCreateFanzineController(fanzineId).stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    };
    controller.onCancel = () {
      sub?.cancel();
    };
    return controller.stream;
  }

  /// High-performance stream that emits the current pages list state immediately upon listening
  /// and forwards all subsequent updates from the broadcast stream.
  static Stream<List<FanzinePage>> watchPages(String fanzineId) {
    final controller = StreamController<List<FanzinePage>>.broadcast();
    StreamSubscription<List<FanzinePage>>? sub;
    controller.onListen = () {
      if (pages.containsKey(fanzineId)) {
        controller.add(pages[fanzineId]!);
      }
      sub = getOrCreatePagesController(fanzineId).stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    };
    controller.onCancel = () {
      sub?.cancel();
    };
    return controller.stream;
  }
}