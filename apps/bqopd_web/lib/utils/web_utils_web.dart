import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:async';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

// Export web_firebase_interop_web relatively to prevent duplicate import resolution issues
export 'web_firebase_interop_web.dart';

/// JS interop extension type for Google Maps Place autocomplete options
@JS()
@anonymous
extension type _AutocompleteOptions._(JSObject _) implements JSObject {
  external factory _AutocompleteOptions({JSArray<JSString>? fields});
}

/// JS interop extension type for Google Place result objects
@JS()
extension type _PlaceResult(JSObject _) implements JSObject {
  external JSString? get formatted_address;
}

/// JS interop extension type for Google Maps Autocomplete instance
@JS('google.maps.places.Autocomplete')
extension type _GoogleAutocomplete._(JSObject _) implements JSObject {
  external factory _GoogleAutocomplete(web.Element element, [_AutocompleteOptions? options]);
  external void addListener(JSString eventName, JSFunction handler);
  external _PlaceResult? getPlace();
}

/// Scrolls an element into view within its scrollable container.
/// Defaults to vertically centering the element within the viewport (`block: 'center'`).
void scrollToElement(String id, {String block = 'center', bool smooth = true}) {
  final el = web.document.getElementById(id);
  if (el != null) {
    el.scrollIntoView(web.ScrollIntoViewOptions(
      behavior: smooth ? 'smooth' : 'auto',
      block: block,
    ));
  }
}

/// Scrolls a specific scrollable container element all the way to the top.
void scrollContainerToTop(String containerId, {bool smooth = true}) {
  final container = web.document.getElementById(containerId);
  if (container != null) {
    container.scrollTo(web.ScrollToOptions(
      top: 0,
      behavior: smooth ? 'smooth' : 'auto',
    ));
  }
}

/// Scrolls a specific scrollable container element all the way to the bottom.
void scrollContainerToBottom(String containerId, {bool smooth = true}) {
  final container = web.document.getElementById(containerId);
  if (container != null) {
    container.scrollTo(web.ScrollToOptions(
      top: container.scrollHeight.toDouble(),
      behavior: smooth ? 'smooth' : 'auto',
    ));
  }
}

/// Centers a target element vertically within its parent scroll container.
/// Uses absolute destination calculation with `scrollTo` to eliminate animation drift.
void centerElementInContainer(String containerId, String targetId, {bool smooth = true}) {
  bool attempt(int remainingTries) {
    final container = web.document.getElementById(containerId);
    final target = web.document.getElementById(targetId);

    if (container != null && target != null) {
      final containerRect = container.getBoundingClientRect();
      final targetRect = target.getBoundingClientRect();

      final currentScrollTop = container.scrollTop.toDouble();
      final targetCenter = targetRect.top + (targetRect.height / 2.0);
      final containerCenter = containerRect.top + (containerRect.height / 2.0);
      final diff = targetCenter - containerCenter;

      container.scrollTo(web.ScrollToOptions(
        top: currentScrollTop + diff,
        behavior: smooth ? 'smooth' : 'auto',
      ));
      return true;
    }

    if (remainingTries > 0) {
      web.window.setTimeout((() {
        attempt(remainingTries - 1);
      }).toJS, 40.toJS);
    }
    return false;
  }

  attempt(5);
}

/// Scrolls a target element to the top of its parent scroll container.
/// The [offset] parameter accounts for container padding (default 16px).
/// Uses absolute destination calculation with `scrollTo` for reliable single-frame alignment.
void scrollElementToTopOfContainer(
    String containerId,
    String targetId, {
      bool smooth = true,
      double offset = 16.0,
    }) {
  bool attempt(int remainingTries) {
    final container = web.document.getElementById(containerId);
    final target = web.document.getElementById(targetId);

    if (container != null && target != null) {
      final containerRect = container.getBoundingClientRect();
      final targetRect = target.getBoundingClientRect();

      final currentScrollTop = container.scrollTop.toDouble();
      final desiredScrollTop = currentScrollTop + (targetRect.top - containerRect.top) - offset;

      container.scrollTo(web.ScrollToOptions(
        top: desiredScrollTop,
        behavior: smooth ? 'smooth' : 'auto',
      ));
      return true;
    }

    if (remainingTries > 0) {
      web.window.setTimeout((() {
        attempt(remainingTries - 1);
      }).toJS, 40.toJS);
    }
    return false;
  }

  attempt(5);
}

/// Inspects the scroll position of [containerId] relative to child items identified by [itemIdBuilder].
/// - Returns 0 if scrolled to the top boundary (<= 15px).
/// - Returns `totalItems - 1` if scrolled to the bottom boundary (within 15px of scrollHeight).
/// - Otherwise, returns the index of the first item whose bounding rect sits comfortably inside
///   the container viewport (within [itemMargin] px), or null if no item is fully in frame.
int? calculateListScrollActiveIndex({
  required String containerId,
  required int totalItems,
  required String Function(int index) itemIdBuilder,
  double boundaryOffset = 15.0,
  double itemMargin = 16.0,
}) {
  final listArea = web.document.getElementById(containerId);
  if (listArea == null) return null;

  // 1. Top boundary check: when scrolled to the very top, snap to index 0
  if (listArea.scrollTop <= boundaryOffset) {
    return 0;
  }

  // 2. Bottom boundary check: when scrolled to the very bottom, snap to last index
  if (listArea.scrollTop + listArea.clientHeight >= listArea.scrollHeight - boundaryOffset) {
    return totalItems - 1;
  }

  final containerRect = listArea.getBoundingClientRect();

  // 3. Find first child item fully in frame
  for (int i = 0; i < totalItems; i++) {
    final itemId = itemIdBuilder(i);
    final itemEl = web.document.getElementById(itemId);
    if (itemEl != null) {
      final itemRect = itemEl.getBoundingClientRect();
      if (itemRect.top >= containerRect.top - itemMargin &&
          itemRect.bottom <= containerRect.bottom + itemMargin) {
        return i;
      }
    }
  }

  return null;
}

/// Client-side implementation of the physical target line indicator and wheel physics coordinator
/// for the Desktop 3rd Column (MultiPageColumnLayout).
class PanelColumnIndicatorCoordinator {
  final String scrollAreaId;
  final String lineId;
  final String cardPrefix;
  final int Function() totalPages;
  final int Function() getCurrentTargetIndex;
  final void Function(int) onTargetChanged;
  final void Function() onUserScrollStart;

  int _currentTargetIndex = 0;
  double _lineY = -1.0;
  bool _isLineLockedAtCenter = false;
  web.HTMLDivElement? _scrollAreaEl;
  JSFunction? _wheelListener;

  PanelColumnIndicatorCoordinator({
    required this.scrollAreaId,
    required this.lineId,
    required this.cardPrefix,
    required this.totalPages,
    required this.getCurrentTargetIndex,
    required this.onTargetChanged,
    required this.onUserScrollStart,
  });

  void init() {
    _currentTargetIndex = getCurrentTargetIndex();
    _attachNativeWheelListener();
    syncLineWithTarget();
  }

  void _attachNativeWheelListener() {
    final el = web.document.getElementById(scrollAreaId) as web.HTMLDivElement?;
    if (el == null) return;
    _scrollAreaEl = el;

    final jsHandler = ((web.WheelEvent e) {
      _handleWheel(e);
    }).toJS;
    _wheelListener = jsHandler;

    // Use non-passive listener (false) so preventDefault() can stop page scrolling while the line moves
    el.addEventListener('wheel', jsHandler, false.toJS);
  }

  void dispose() {
    if (_scrollAreaEl != null && _wheelListener != null) {
      _scrollAreaEl!.removeEventListener('wheel', _wheelListener!, false.toJS);
      _wheelListener = null;
      _scrollAreaEl = null;
    }
  }

  double? _getCardCenterY(int pageIndex) {
    final scrollArea = web.document.getElementById(scrollAreaId);
    final card = web.document.getElementById('$cardPrefix$pageIndex');
    if (scrollArea == null || card == null) return null;
    final areaRect = scrollArea.getBoundingClientRect();
    final cardRect = card.getBoundingClientRect();
    return (cardRect.top - areaRect.top) + (cardRect.height / 2.0);
  }

  void syncLineWithTarget({int tries = 6}) {
    _currentTargetIndex = getCurrentTargetIndex();
    final scrollArea = web.document.getElementById(scrollAreaId);
    final card = web.document.getElementById('$cardPrefix$_currentTargetIndex');
    if (scrollArea != null &&
        card != null &&
        card.getBoundingClientRect().height > 0) {
      alignLineToTarget();
      return;
    }
    if (tries > 0) {
      web.window.setTimeout((() {
        syncLineWithTarget(tries: tries - 1);
      }).toJS, 40.toJS);
    }
  }

  void alignLineToTarget() {
    final scrollArea = web.document.getElementById(scrollAreaId);
    if (scrollArea == null) return;
    final double areaHeight = scrollArea.clientHeight.toDouble();
    if (areaHeight <= 0) return;
    final double viewportCenter = areaHeight / 2.0;

    final cardCenter = _getCardCenterY(_currentTargetIndex);
    if (cardCenter != null) {
      _lineY = cardCenter;
      final diffFromCenter = (_lineY - viewportCenter).abs();
      _isLineLockedAtCenter = diffFromCenter <= 6.0;
      if (_isLineLockedAtCenter) {
        _lineY = viewportCenter;
      }
      _updateLineDOM();
      _updateCardHighlightsDOM();
    }
  }

  void _handleWheel(web.WheelEvent e) {
    onUserScrollStart();

    final scrollArea = web.document.getElementById(scrollAreaId);
    if (scrollArea == null) return;

    final double areaHeight = scrollArea.clientHeight.toDouble();
    if (areaHeight <= 0) return;
    final double viewportCenter = areaHeight / 2.0;
    final double scrollTop = scrollArea.scrollTop.toDouble();
    final double maxScrollTop =
    (scrollArea.scrollHeight - scrollArea.clientHeight).toDouble();
    final bool isAtTop = scrollTop <= 2.0;
    final bool isAtBottom = scrollTop >= (maxScrollTop - 4.0);

    final double delta = e.deltaY.toDouble();
    if (delta == 0) return;

    final total = totalPages();
    if (total == 0) return;
    final topCardCenter = _getCardCenterY(0) ?? 16.0;
    final bottomCardCenter = _getCardCenterY(total - 1) ?? (areaHeight - 16.0);

    if (!_isLineLockedAtCenter) {
      // Phase 1: Line is moving towards or away from the viewport vertical center
      if (_lineY < viewportCenter) {
        // Line is currently above center
        if (delta > 0) {
          // Scrolling down (towards center) -> move line down, NOT page
          e.preventDefault();
          _lineY += delta;
          if (_lineY >= viewportCenter) {
            _lineY = viewportCenter;
            _isLineLockedAtCenter = true;
          }
          _onLinePositionChanged();
        } else {
          // Scrolling up (away from center towards top widget midpoint)
          e.preventDefault();
          _lineY = math.max(topCardCenter, _lineY + delta);
          _onLinePositionChanged();
        }
      } else {
        // Line is currently below center
        if (delta < 0) {
          // Scrolling up (towards center) -> move line up, NOT page
          e.preventDefault();
          _lineY += delta;
          if (_lineY <= viewportCenter) {
            _lineY = viewportCenter;
            _isLineLockedAtCenter = true;
          }
          _onLinePositionChanged();
        } else {
          // Scrolling down (away from center towards bottom widget midpoint)
          e.preventDefault();
          _lineY = math.min(bottomCardCenter, _lineY + delta);
          _onLinePositionChanged();
        }
      }
    } else {
      // Phase 2: Line is locked at viewport center
      if (delta < 0 && isAtTop) {
        // Scrolled all the way to the top boundary: move line up towards top widget midpoint
        if (topCardCenter < viewportCenter) {
          e.preventDefault();
          _lineY = math.max(topCardCenter, _lineY + delta);
          if (_lineY < viewportCenter) {
            _isLineLockedAtCenter = false;
          }
          _onLinePositionChanged();
        }
      } else if (delta > 0 && isAtBottom) {
        // Scrolled all the way to the bottom boundary: move line down towards bottom widget midpoint
        if (bottomCardCenter > viewportCenter) {
          e.preventDefault();
          _lineY = math.min(bottomCardCenter, _lineY + delta);
          if (_lineY > viewportCenter) {
            _isLineLockedAtCenter = false;
          }
          _onLinePositionChanged();
        }
      } else {
        // Normal scrolling: line stays locked at viewport center
        _lineY = viewportCenter;
        _updateLineDOM();
      }
    }
  }

  void handleScroll() {
    final scrollArea = web.document.getElementById(scrollAreaId);
    if (scrollArea == null) return;
    final double areaHeight = scrollArea.clientHeight.toDouble();
    final double viewportCenter = areaHeight / 2.0;

    if (_isLineLockedAtCenter) {
      _lineY = viewportCenter;
      _updateLineDOM();
      final cardIdx = _findCardUnderLine(_lineY);
      if (cardIdx != null && cardIdx != _currentTargetIndex) {
        _currentTargetIndex = cardIdx;
        _updateCardHighlightsDOM();
        onTargetChanged(cardIdx);
      }
    }
  }

  void _onLinePositionChanged() {
    _updateLineDOM();
    final cardIdx = _findCardUnderLine(_lineY);
    if (cardIdx != null && cardIdx != _currentTargetIndex) {
      _currentTargetIndex = cardIdx;
      _updateCardHighlightsDOM();
      onTargetChanged(cardIdx);
    }
  }

  int? _findCardUnderLine(double lineY) {
    final scrollArea = web.document.getElementById(scrollAreaId);
    if (scrollArea == null) return null;
    final areaRect = scrollArea.getBoundingClientRect();
    final total = totalPages();

    for (int i = 0; i < total; i++) {
      final card = web.document.getElementById('$cardPrefix$i');
      if (card != null) {
        final cardRect = card.getBoundingClientRect();
        final cardTop = cardRect.top - areaRect.top;
        final cardBottom = cardRect.bottom - areaRect.top;
        if (lineY >= cardTop && lineY <= cardBottom) {
          return i;
        }
      }
    }

    // Fallback: choose whichever card's center midpoint is closest
    int closestIdx = 0;
    double minDiff = 999999.0;
    for (int i = 0; i < total; i++) {
      final center = _getCardCenterY(i);
      if (center != null) {
        final diff = (center - lineY).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestIdx = i;
        }
      }
    }
    return closestIdx;
  }

  void _updateLineDOM() {
    final line = web.document.getElementById(lineId) as web.HTMLDivElement?;
    if (line != null && _lineY >= 0) {
      line.style.top = '${_lineY.toStringAsFixed(1)}px';
      line.style.display = 'flex';
    }
  }

  void _updateCardHighlightsDOM() {
    final total = totalPages();
    for (int i = 0; i < total; i++) {
      final el = web.document.getElementById('$cardPrefix$i') as web.HTMLDivElement?;
      if (el != null) {
        if (i == _currentTargetIndex) {
          el.classList.remove('non-target');
          el.classList.add('target');
        } else {
          el.classList.remove('target');
          el.classList.add('non-target');
        }
      }
    }
  }

  void handleCardTap(int i) {
    _currentTargetIndex = i;
    _updateCardHighlightsDOM();
    final scrollArea = web.document.getElementById(scrollAreaId);
    if (scrollArea != null) {
      final double areaHeight = scrollArea.clientHeight.toDouble();
      final double viewportCenter = areaHeight / 2.0;
      _lineY = viewportCenter;
      _isLineLockedAtCenter = true;
      _updateLineDOM();
    }
  }
}

/// Copies text to the system clipboard in web environments using Navigator.
void copyToClipboard(String text) {
  try {
    web.window.navigator.clipboard.writeText(text);
  } catch (e) {
    print('[copyToClipboard Error] $e');
  }
}

/// Reads the selected file from the DOM element directly using pure Dart and package:web.
void readSelectedFile(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  final input = web.document.getElementById(inputId) as web.HTMLInputElement?;
  if (input == null) {
    print('[DART FILE READER] Input element with ID "$inputId" not found.');
    return;
  }

  final files = input.files;
  if (files == null || files.length == 0) {
    print('[DART FILE READER] No files chosen.');
    return;
  }

  final file = files.item(0);
  if (file == null) {
    print('[DART FILE READER] Selected file is null.');
    return;
  }

  print('[DART FILE READER] Loading: ${file.name} (${file.size} bytes)');

  final reader = web.FileReader();
  reader.onload = (web.Event event) {
    final result = reader.result;
    if (result == null) {
      print('[DART FILE READER] FileReader result is null.');
      return;
    }
    final dataUrl = (result as JSString).toDart;
    final splitIndex = dataUrl.indexOf(',');
    if (splitIndex == -1) {
      print('[DART FILE READER] Invalid DataURL format.');
      return;
    }
    final base64 = dataUrl.substring(splitIndex + 1);
    final objectUrl = web.URL.createObjectURL(file);
    print('[DART FILE READER] Success. Triggering callback.');
    callback(base64, file.name, objectUrl);
  }.toJS;

  reader.onerror = (web.Event event) {
    print('[DART FILE READER] FileReader error encountered.');
  }.toJS;

  reader.readAsDataURL(file);
}

/// Creates or triggers a hidden native file input and monitors changes completely within Dart.
void triggerFilePicker(String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  var input = web.document.getElementById(inputId) as web.HTMLInputElement?;
  if (input == null) {
    input = web.document.createElement('input') as web.HTMLInputElement
      ..id = inputId
      ..type = 'file'
      ..accept = 'image/*'
      ..style.display = 'none';
    web.document.body?.append(input);
  }

  input.onchange = (web.Event event) {
    readSelectedFile(inputId, callback);
  }.toJS;

  input.click();
}

/// Asynchronously loads an image object to extract its native width and height metrics on client.
Future<Map<String, int>> getImageDimensions(String objectUrl) {
  final completer = Completer<Map<String, int>>();
  final img = web.document.createElement('img') as web.HTMLImageElement;

  img.onload = (web.Event event) {
    completer.complete({
      'width': img.naturalWidth,
      'height': img.naturalHeight,
    });
  }.toJS;

  img.onerror = (web.Event event) {
    completer.complete({
      'width': 0,
      'height': 0,
    });
  }.toJS;

  img.src = objectUrl;
  return completer.future;
}

/// Client-side implementation of retrieving an input element value with type-safe inspection.
String getInputValue(dynamic event) {
  if (event == null) return '';

  // 1. Direct package:web Event checking
  try {
    if (event is web.Event) {
      final target = event.target;
      if (target is web.HTMLInputElement) {
        return target.value;
      }
      if (target is web.HTMLTextAreaElement) {
        return target.value;
      }
      if (target is web.HTMLSelectElement) {
        return target.value;
      }
    }
  } catch (e) {
    print('[getInputValue web.Event Error] $e');
  }

  // 2. dart:js_interop and dart:js_interop_unsafe inspection on JSObjects
  try {
    if (event is JSObject) {
      if (event.has('target')) {
        final target = event['target'];
        if (target != null && target is JSObject && target.has('value')) {
          final val = target['value'];
          if (val != null) {
            return val.dartify()?.toString() ?? '';
          }
        }
      }
    }
  } catch (e) {
    print('[getInputValue js_interop Error] $e');
  }

  // 3. Fallback to dynamic property invocation for legacy wrapped objects
  try {
    final target = (event as dynamic).target;
    if (target != null) {
      final val = target.value;
      if (val != null) {
        return val.toString();
      }
    }
  } catch (e) {
    print('[getInputValue dynamic Fallback Error] $e');
  }

  return '';
}

/// Checks the current browser URL path and performs a client-side route replacement
/// to the vanity url if accessed via the legacy /reader/:fanzineId route.
void redirectFanzinePath(dynamic context, String shortCode) {
  try {
    final currentPath = web.window.location.pathname;
    if (currentPath.startsWith('/reader/') && context is BuildContext) {
      Router.of(context).replace('/$shortCode');
    }
  } catch (e) {
    print('[redirectFanzinePath Error] $e');
  }
}

/// Browser-specific preference saving using package:web.
void saveLocalPreference(String key, String value) {
  web.window.localStorage.setItem(key, value);
}

/// Browser-specific preference retrieval using package:web.
String? getLocalPreference(String key) {
  return web.window.localStorage.getItem(key);
}

/// Browser-specific implementation for opening windows safely.
void openWindow(String url, String target) {
  web.window.open(url, target);
}

/// Dynamically binds Google Places Autocomplete to an input element.
/// Uses the central window.initAddressAutocomplete polyfill in firebase_init.js if present,
/// falling back to direct JS SDK instantiation.
void initAddressAutocomplete(String inputId, void Function(String) callback) {
  final input = web.document.getElementById(inputId) as web.HTMLInputElement?;
  if (input == null) return;

  final jsWindow = web.window as JSObject;

  // 1. Delegate to central window.initAddressAutocomplete in firebase_init.js
  if (jsWindow.has('initAddressAutocomplete')) {
    try {
      final fn = jsWindow['initAddressAutocomplete'] as JSFunction?;
      if (fn != null) {
        fn.callAsFunction(
          null,
          inputId.toJS,
          ((JSString address) => callback(address.toDart)).toJS,
        );
        return;
      }
    } catch (e) {
      print('[initAddressAutocomplete central call failed, falling back] $e');
    }
  }

  // 2. Direct Places SDK initialization
  if (!jsWindow.has('google')) {
    web.window.setTimeout((() {
      initAddressAutocomplete(inputId, callback);
    }).toJS, 150.toJS);
    return;
  }

  final google = jsWindow['google'];
  if (google == null || google is! JSObject || !google.has('maps')) {
    web.window.setTimeout((() {
      initAddressAutocomplete(inputId, callback);
    }).toJS, 150.toJS);
    return;
  }

  final maps = google['maps'];
  if (maps == null || maps is! JSObject || !maps.has('places')) {
    web.window.setTimeout((() {
      initAddressAutocomplete(inputId, callback);
    }).toJS, 150.toJS);
    return;
  }

  try {
    final options = _AutocompleteOptions(
      fields: ['formatted_address'.toJS].toJS,
    );
    final autocomplete = _GoogleAutocomplete(input, options);
    autocomplete.addListener('place_changed'.toJS, (() {
      final place = autocomplete.getPlace();
      if (place != null) {
        final formatted = place.formatted_address;
        if (formatted != null) {
          callback(formatted.toDart);
        }
      }
    }).toJS);
  } catch (e) {
    print('[initAddressAutocomplete Error] $e');
  }
}

/// Returns the current pathname from the browser's window location.
String getCurrentPath() {
  try {
    return web.window.location.pathname;
  } catch (_) {
    return '';
  }
}