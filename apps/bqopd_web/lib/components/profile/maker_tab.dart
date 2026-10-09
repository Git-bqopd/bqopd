import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../../utils/web_firebase_interop.dart';
import '../../utils/web_utils.dart';
import '../../utils/unsaved_fanzine_registry.dart';
import '../../utils/publisher_compiler.dart';
import '../historical_letter_card.dart';
import '../fanzine_thumbnail_card.dart';
import './maker_upload_form.dart';

/// Maker Tab content displaying publications and folios.
/// Streams live works and renders both published and draft lists using FanzineThumbnailCard.
class ProfileMakerTab extends StatefulComponent {
  final String targetUserId;
  final bool isMe;
  final bool canSeeDrafts;
  final IUserRepository userRepository;
  final AuthState? authState;
  final String? initialSubTab;
  final ValueChanged<String>? onSubTabChanged;

  const ProfileMakerTab({
    required this.targetUserId,
    required this.isMe,
    required this.canSeeDrafts,
    required this.userRepository,
    this.authState,
    this.initialSubTab,
    this.onSubTabChanged,
    super.key,
  });

  @override
  State<ProfileMakerTab> createState() => _ProfileMakerTabState();
}

class _ProfileMakerTabState extends State<ProfileMakerTab> {
  bool _showDrafts = false;
  bool _showMakerModal = false;
  bool _showIndicia = false;
  String _makerModalMode = 'options'; // 'options', 'upload', 'radius_letters'

  List<Map<String, dynamic>> _userWorks = [];
  StreamSubscription? _worksSub;
  bool _loading = true;

  // Holds the ID and shortcode of the folio currently queued for deletion
  String? _pendingDeleteId;
  String? _pendingDeleteShortcode;

  // Radius Letters configuration state
  String _radiusAddress = '';
  int _radiusMiles = 50;
  bool _radiusLoading = false;
  String? _radiusError;
  String? _radiusProgressStatus;

  @override
  void initState() {
    super.initState();
    if (component.initialSubTab == 'drafts') {
      _showDrafts = true;
    } else if (component.initialSubTab == 'published') {
      _showDrafts = false;
    }

    if (kIsWeb) {
      Future.microtask(() {
        if (mounted) {
          _listenToWorks();
        }
      });
    }
  }

  @override
  void didUpdateComponent(ProfileMakerTab oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.initialSubTab != component.initialSubTab) {
      if (component.initialSubTab == 'drafts') {
        _showDrafts = true;
      } else if (component.initialSubTab == 'published') {
        _showDrafts = false;
      }
    }
    if (oldComponent.targetUserId != component.targetUserId && kIsWeb) {
      _listenToWorks();
    }
  }

  @override
  void dispose() {
    _worksSub?.cancel();
    super.dispose();
  }

  void _selectDraftMode(bool showDrafts) {
    setState(() => _showDrafts = showDrafts);
    if (component.onSubTabChanged != null) {
      component.onSubTabChanged!(showDrafts ? 'drafts' : 'published');
    }
  }

  void _listenToWorks() {
    _worksSub?.cancel();
    setState(() => _loading = true);

    _worksSub = component.userRepository
        .watchUserWorks(component.targetUserId)
        .listen((works) {
      if (mounted) {
        setState(() {
          _userWorks = works;
          _loading = false;
        });
      }
    });
  }

  DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Map) {
      if (value['__type'] == 'timestamp' && value['iso'] != null) {
        return DateTime.tryParse(value['iso'].toString());
      }
    }
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    return null;
  }

  List<Map<String, dynamic>> get _publishedWorks {
    final list = _userWorks.where((w) => w['isLive'] == true).toList();
    list.sort((a, b) {
      final aTime = _parseDateValue(a['publishedAt'] ??
          a['updatedAt'] ??
          a['creationDate'] ??
          a['timestamp']);
      final bTime = _parseDateValue(b['publishedAt'] ??
          b['updatedAt'] ??
          b['creationDate'] ??
          b['timestamp']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  List<Map<String, dynamic>> get _draftWorks {
    final list = _userWorks.where((w) => w['isLive'] != true).toList();
    list.sort((a, b) {
      final aTime = _parseDateValue(
          a['updatedAt'] ?? a['creationDate'] ?? a['timestamp']);
      final bTime = _parseDateValue(
          b['updatedAt'] ?? b['creationDate'] ?? b['timestamp']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  Future<String> _generateUniqueTempShortcode() async {
    final String? email = component.authState?.user?.email;
    final bool useVanity =
        email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

    bool isUnique = false;
    String code = "";
    int retries = 0;

    while (!isUnique && retries < 15) {
      final String candidate = useVanity
          ? ShortcodeGenerator.generateVanityCode()
          : ShortcodeGenerator.generateStandardCode();

      final String codeUpper = candidate.toUpperCase();
      final docRes = await fsGetDoc('shortcodes/$codeUpper');
      final Map<String, dynamic> doc = jsonDecode(docRes);

      final isLocalCollision = UnsavedFanzineRegistry.hasCode(candidate);

      if (doc['exists'] != true && !isLocalCollision) {
        isUnique = true;
        code = candidate;
      }
      retries++;
    }

    if (code.isEmpty) {
      code =
      'TEMP_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
    return code;
  }

  Future<void> _createFolio() async {
    try {
      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'new folio name',
        ownerId: component.targetUserId,
        curators: [component.targetUserId],
        collections: [component.targetUserId],
        type: FanzineType.folio,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
      );

      UnsavedFanzineRegistry.add(newFanzine, []);
      setState(() => _showMakerModal = false);
      Router.of(context).replace('/$shortCode/maker');
    } catch (e) {
      print("Error creating folio: $e");
    }
  }

  Future<void> _createCalendar() async {
    try {
      final fanzineId = 'calendar_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();

      final newFanzine = Fanzine(
        id: fanzineId,
        title: 'Convention Calendar 2026',
        ownerId: component.targetUserId,
        curators: [component.targetUserId],
        collections: [component.targetUserId],
        type: FanzineType.calendar,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: true,
      );

      final page1Id = 'page1_${DateTime.now().millisecondsSinceEpoch}';
      final page2Id = 'page2_${DateTime.now().millisecondsSinceEpoch}';

      final List<FanzinePage> pages = [
        FanzinePage(
            id: page1Id,
            pageNumber: 1,
            templateId: 'calendar_left',
            status: 'ready'),
        FanzinePage(
            id: page2Id,
            pageNumber: 2,
            templateId: 'calendar_right',
            status: 'ready'),
      ];

      UnsavedFanzineRegistry.add(newFanzine, pages);
      setState(() => _showMakerModal = false);
      Router.of(context).replace('/$shortCode/maker');
    } catch (e) {
      print("Error creating calendar: $e");
    }
  }

  double _calculateDistanceMiles(
      double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)) * 0.621371; // km to miles
  }

  String _cleanHistoricalLocation(String raw) {
    var loc = raw.trim();
    loc = loc.replaceAll(RegExp(r'\bWis\b\.?', caseSensitive: false), 'WI');
    loc = loc.replaceAll(RegExp(r'\bIll\b\.?', caseSensitive: false), 'IL');
    loc = loc.replaceAll(RegExp(r'\bMich\b\.?', caseSensitive: false), 'MI');
    loc = loc.replaceAll(RegExp(r'\bMinn\b\.?', caseSensitive: false), 'MN');
    loc = loc.replaceAll(RegExp(r'\bPenn\b\.?', caseSensitive: false), 'PA');
    loc = loc.replaceAll(RegExp(r'\bN\.\s*D\b\.?', caseSensitive: false), 'ND');
    loc = loc.replaceAll(RegExp(r'\bS\.\s*D\b\.?', caseSensitive: false), 'SD');
    loc = loc.replaceAll(RegExp(r'\bCal\b\.?', caseSensitive: false), 'CA');
    loc = loc.replaceAll(RegExp(r'\bCalif\b\.?', caseSensitive: false), 'CA');
    loc = loc.replaceAll(RegExp(r'\bInd\b\.?', caseSensitive: false), 'IN');
    loc = loc.replaceAll(RegExp(r'\bMo\b\.?', caseSensitive: false), 'MO');
    loc = loc.replaceAll(RegExp(r'\bMass\b\.?', caseSensitive: false), 'MA');
    loc = loc.replaceAll(RegExp(r'\bConn\b\.?', caseSensitive: false), 'CT');
    loc = loc.replaceAll(RegExp(r'\bWash\b\.?', caseSensitive: false), 'WA');

    if (loc.contains(',')) {
      final parts = loc.split(',');
      if (parts.length >= 2) {
        final last = parts[parts.length - 1].trim();
        final secondLast = parts[parts.length - 2].trim();
        loc = '$secondLast, $last';
      }
    }
    return loc;
  }

  Future<void> _createRadiusLettersFolio() async {
    final targetAddr = _radiusAddress.trim();
    if (targetAddr.isEmpty) {
      setState(() => _radiusError = 'Please enter an address or city.');
      return;
    }

    setState(() {
      _radiusLoading = true;
      _radiusError = null;
      _radiusProgressStatus = 'Geocoding center address...';
    });

    try {
      // 1. Geocode target address
      Map<String, double>? targetCoords;
      final targetGeoJson = await geocodeAddress(targetAddr);
      if (targetGeoJson != null && targetGeoJson.isNotEmpty) {
        final decoded = jsonDecode(targetGeoJson);
        if (decoded != null && decoded['lat'] != null && decoded['lng'] != null) {
          targetCoords = {
            'lat': (decoded['lat'] as num).toDouble(),
            'lng': (decoded['lng'] as num).toDouble(),
          };
        }
      }

      print('[RadiusLetters] Center address "$targetAddr" coords: $targetCoords');

      setState(() {
        _radiusProgressStatus = 'Scanning historical letters database...';
      });

      // 2. Fetch all comments to find historical transcribed letters
      final commentsRes =
      await fsQuery('artifacts/bqopd/public/data/comments', '', '', '', '');
      final List decodedComments = jsonDecode(commentsRes) as List;

      final List<Map<String, dynamic>> letterComments = [];
      for (final item in decodedComments) {
        final data = Map<String, dynamic>.from(item['data'] as Map);
        data['_id'] = item['id'];
        final isLetter = data['sourceType'] == 'letter_column' ||
            (data['location'] != null &&
                data['location'].toString().trim().isNotEmpty);
        if (isLetter) {
          letterComments.add(data);
        }
      }

      if (letterComments.isEmpty) {
        setState(() {
          _radiusLoading = false;
          _radiusError = 'No transcribed letters found in database.';
        });
        return;
      }

      // 3. Geocode and filter letters within the given distance
      setState(() {
        _radiusProgressStatus = 'Calculating distances for ${letterComments.length} letters...';
      });

      final Map<String, Map<String, double>?> locationCache = {};
      final List<Map<String, dynamic>> matchingLetters = [];

      for (final letter in letterComments) {
        String loc = (letter['location'] ?? '').toString().trim();

        if (loc.isEmpty && letter['userId'] != null) {
          final uid = letter['userId'].toString();
          if (!uid.startsWith('archival_')) {
            try {
              final pRes = await fsGetDoc('profiles/$uid');
              final pDoc = jsonDecode(pRes);
              if (pDoc['exists'] == true) {
                final pData = pDoc['data'] as Map<String, dynamic>? ?? {};
                loc = (pData['location'] ?? pData['city'] ?? '').toString().trim();
                if (pData['state'] != null &&
                    pData['state'].toString().isNotEmpty) {
                  loc +=
                      (loc.isNotEmpty ? ', ' : '') + pData['state'].toString().trim();
                }
              }
            } catch (_) {}
          }
        }

        if (loc.isEmpty) continue;

        bool isWithin = false;
        final cleanLoc = _cleanHistoricalLocation(loc);

        if (targetCoords != null) {
          if (!locationCache.containsKey(cleanLoc)) {
            final geoJson = await geocodeAddress(cleanLoc);
            if (geoJson != null && geoJson.isNotEmpty) {
              final decoded = jsonDecode(geoJson);
              if (decoded != null &&
                  decoded['lat'] != null &&
                  decoded['lng'] != null) {
                locationCache[cleanLoc] = {
                  'lat': (decoded['lat'] as num).toDouble(),
                  'lng': (decoded['lng'] as num).toDouble(),
                };
              } else {
                locationCache[cleanLoc] = null;
              }
            } else {
              locationCache[cleanLoc] = null;
            }
          }

          final letterCoords = locationCache[cleanLoc];
          if (letterCoords != null) {
            final distance = _calculateDistanceMiles(
              targetCoords['lat']!,
              targetCoords['lng']!,
              letterCoords['lat']!,
              letterCoords['lng']!,
            );
            if (distance <= _radiusMiles) {
              isWithin = true;
              letter['_calculatedDistanceMiles'] = distance;
            }
          }
        }

        if (!isWithin && targetCoords == null) {
          final cleanTarget = targetAddr.toLowerCase();
          final locLower = loc.toLowerCase();
          if (locLower.contains(cleanTarget) || cleanTarget.contains(locLower)) {
            isWithin = true;
          }
        }

        if (isWithin) {
          matchingLetters.add(letter);
        }
      }

      if (matchingLetters.isEmpty) {
        setState(() {
          _radiusLoading = false;
          _radiusProgressStatus = null;
          _radiusError =
          'No letters found within $_radiusMiles miles of "$targetAddr". Try increasing the distance.';
        });
        return;
      }

      setState(() {
        _radiusProgressStatus = 'Resolving publications and page scans...';
      });

      // Sort matching letters by ascending distance
      matchingLetters.sort((a, b) {
        final double distA = (a['_calculatedDistanceMiles'] as double?) ?? 0;
        final double distB = (b['_calculatedDistanceMiles'] as double?) ?? 0;
        return distA.compareTo(distB);
      });

      final List<HistoricalLetterEntry> resolvedEntries = [];
      for (final letter in matchingLetters) {
        final entry = await HistoricalLetterEntry.resolveComplete(
          rawComment: letter,
          distanceMiles: letter['_calculatedDistanceMiles'] as double?,
        );
        resolvedEntries.add(entry);
      }

      final fanzineId = 'folio_${DateTime.now().millisecondsSinceEpoch}';
      final shortCode = await _generateUniqueTempShortcode();
      final String folioTitle = 'Letters near $targetAddr';

      setState(() {
        _radiusProgressStatus = 'Compiling connected publisher pages...';
      });

      // Construct ONE continuous markdown text flow containing all resolved letters
      final fullMarkdownBuffer = StringBuffer();
      for (final entry in resolvedEntries) {
        fullMarkdownBuffer.write(entry.toPublisherMarkdown());
        fullMarkdownBuffer.writeln();
      }
      final fullText = fullMarkdownBuffer.toString().trim();

      // Compile multi-page continuous layout where overflow lines continue seamlessly
      final List<FanzinePage> pages = await PublisherCompiler.compileAndPublishMultiPage(
        fanzineId: fanzineId,
        fullText: fullText,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _radiusProgressStatus = 'Compiling publisher text page $current of $total...';
            });
          }
        },
      );

      final newFanzine = Fanzine(
        id: fanzineId,
        title: folioTitle,
        ownerId: component.targetUserId,
        curators: [component.targetUserId],
        collections: [component.targetUserId],
        type: FanzineType.folio,
        isLive: false,
        processingStatus: 'complete',
        shortCode: shortCode,
        twoPage: true,
        hasCover: false,
      );

      UnsavedFanzineRegistry.add(newFanzine, pages);
      setState(() {
        _showMakerModal = false;
        _radiusLoading = false;
        _radiusProgressStatus = null;
      });
      Router.of(context).replace('/$shortCode/maker');
    } catch (e) {
      print("Error creating radius letters folio: $e");
      if (mounted) {
        setState(() {
          _radiusLoading = false;
          _radiusProgressStatus = null;
          _radiusError = 'Failed to generate folio: $e';
        });
      }
    }
  }

  Component _buildMakerOptionsContent() {
    return div(
      [
        h1([Component.text('maker options')],
            classes: 'font-bold text-lg text-center mb-6',
            attributes: const {'style': 'margin-top: 0;'}),
        button(
            [Component.text("single image")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style':
              'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => setState(() => _makerModalMode = 'upload')}),
        button(
            [Component.text("folio")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style':
              'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => _createFolio()}),
        button(
            [Component.text("calendar")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style':
              'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) => _createCalendar()}),
        button(
            [Component.text("radius letters")],
            classes: 'profile-btn mb-4',
            attributes: const {
              'style':
              'width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white; margin-bottom: 16px; text-transform: none;'
            },
            events: {'click': (e) {
              setState(() {
                _makerModalMode = 'radius_letters';
                _radiusAddress = '';
                _radiusError = null;
                _radiusLoading = false;
                _radiusProgressStatus = null;
              });
              Timer(const Duration(milliseconds: 120), () {
                initAddressAutocomplete(
                    'radius-letters-address-input', (String address) {
                  setState(() => _radiusAddress = address);
                });
              });
            }}),
      ],
      classes:
      'white-sticker p-6 w-full h-full flex flex-col justify-center items-center',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 24px; box-sizing: border-box; width: 100%; height: 100%;'
      },
    );
  }

  Component _buildRadiusLettersForm() {
    return div(
      [
        div(
          [
            button(
              [
                span([Component.text('arrow_back')],
                    classes: 'material-symbols-outlined',
                    attributes: const {'style': 'font-size: 16px; margin-right: 4px;'}),
                Component.text('options')
              ],
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                'display: inline-flex; align-items: center; padding: 4px 10px; font-size: 11px; font-weight: bold; border: 1px solid #ddd; background: white; cursor: pointer;'
              },
              events: {'click': (e) => setState(() => _makerModalMode = 'options')},
            ),
            h2([Component.text("radius letters")],
                classes: 'font-bold text-sm text-black',
                attributes: const {'style': 'margin: 0; margin-left: auto; text-transform: lowercase;'}),
          ],
          attributes: const {
            'style':
            'display: flex; align-items: center; width: 100%; margin-bottom: 16px;'
          },
        ),
        p([
          Component.text(
              "Enter an address or city to compile historical letters sent from within a given distance into a continuous publisher folio.")
        ],
            attributes: const {
              'style':
              'font-size: 12px; color: #555; line-height: 1.4; margin: 0 0 16px 0; text-align: left; width: 100%;'
            }),
        div(
          [
            span([Component.text("ADDRESS OR CITY")],
                classes: 'text-xs font-bold text-gray-600',
                attributes: const {'style': 'margin-bottom: 4px; display: block; text-align: left;'}),
            input(
              attributes: {
                'type': 'text',
                'id': 'radius-letters-address-input',
                'placeholder': 'e.g. Milwaukee, WI or 123 Main St...',
                'value': _radiusAddress,
                'style':
                'width: 100%; padding: 10px 12px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; font-size: 13px; background: white; outline: none; margin-bottom: 0;',
                if (_radiusLoading) 'disabled': 'true'
              },
              events: {'input': (e) => setState(() => _radiusAddress = getInputValue(e))},
            ),
          ],
          attributes: const {'style': 'width: 100%; margin-bottom: 14px;'},
        ),
        div(
          [
            span([Component.text("SEARCH RADIUS")],
                classes: 'text-xs font-bold text-gray-600',
                attributes: const {'style': 'margin-bottom: 6px; display: block; text-align: left;'}),
            div(
              [
                for (final mi in [10, 25, 50, 100, 250])
                  button(
                    [Component.text('$mi mi')],
                    attributes: {
                      'type': 'button',
                      'style':
                      'padding: 6px 12px; font-size: 11px; font-weight: bold; cursor: pointer; border-radius: 4px; border: 1px solid ${_radiusMiles == mi ? "#6750A4" : "#ccc"}; background: ${_radiusMiles == mi ? "#E8DEF8" : "white"}; color: ${_radiusMiles == mi ? "#1D192B" : "#555"}; transition: all 0.15s;'
                    },
                    events: {'click': (e) => setState(() => _radiusMiles = mi)},
                  )
              ],
              attributes: const {
                'style':
                'display: flex; gap: 6px; width: 100%; flex-wrap: wrap;'
              },
            ),
          ],
          attributes: const {'style': 'width: 100%; margin-bottom: 16px;'},
        ),
        if (_radiusProgressStatus != null)
          p([
            span([Component.text('progress_activity')],
                classes: 'material-symbols-outlined',
                attributes: const {
                  'style':
                  'font-size: 14px; margin-right: 6px; vertical-align: middle; animation: spin 1s linear infinite;'
                }),
            Component.text(_radiusProgressStatus!)
          ],
              attributes: const {
                'style':
                'font-size: 11px; color: #6750A4; font-weight: bold; margin: 0 0 12px 0; text-align: left; width: 100%;'
              }),
        if (_radiusError != null)
          p([Component.text(_radiusError!)],
              attributes: const {
                'style':
                'font-size: 11px; font-weight: bold; color: #ef4444; margin: 0 0 12px 0; text-align: left; width: 100%; line-height: 1.4;'
              }),
        div(
          [
            button(
              [Component.text("cancel")],
              classes: 'profile-btn',
              attributes: const {
                'type': 'button',
                'style':
                'padding: 8px 16px; font-size: 11px; font-weight: bold; border: 1px solid #ccc; background: white; cursor: pointer; height: 36px;'
              },
              events: {'click': (e) => setState(() => _makerModalMode = 'options')},
            ),
            button(
              [
                if (_radiusLoading)
                  span([Component.text('progress_activity')],
                      classes: 'material-symbols-outlined',
                      attributes: const {
                        'style':
                        'font-size: 16px; margin-right: 6px; animation: spin 1s linear infinite;'
                      })
                else
                  span([Component.text('menu_book')],
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 16px; margin-right: 6px;'}),
                Component.text(_radiusLoading ? "compiling folio..." : "create folio")
              ],
              classes: 'btn-primary nav-pill mb-0',
              attributes: {
                'type': 'button',
                'style':
                'padding: 8px 18px; font-size: 11px; font-weight: bold; background-color: #6750A4; border: none; border-radius: 50px; color: white; cursor: pointer; display: inline-flex; align-items: center; height: 36px;',
                if (_radiusLoading) 'disabled': 'true'
              },
              events: {'click': (e) => _createRadiusLettersFolio()},
            ),
          ],
          attributes: const {
            'style':
            'display: flex; gap: 8px; justify-content: flex-end; width: 100%; margin-top: auto;'
          },
        )
      ],
      classes: 'white-sticker p-6 w-full h-full flex flex-col justify-start items-center',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; justify-content: flex-start; align-items: center; padding: 24px; box-sizing: border-box; width: 100%; height: 100%;'
      },
    );
  }

  Component _buildMakerModalOverlay() {
    final bool isUploadMode = _makerModalMode == 'upload';
    final bool isRadiusLettersMode = _makerModalMode == 'radius_letters';
    return div(
      [
        if (!isUploadMode)
          div(
            [
              button(
                [Component.text('close')],
                classes: 'modal-close-btn',
                attributes: const {
                  'style':
                  'position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 18px; font-weight: bold; cursor: pointer; color: #555; line-height: 1; transition: color 0.15s; outline: none; z-index: 200;'
                },
                events: {'click': (e) => setState(() => _showMakerModal = false)},
              ),
              if (isRadiusLettersMode)
                _buildRadiusLettersForm()
              else
                _buildMakerOptionsContent(),
            ],
            classes: 'manila-envelope',
            attributes: const {
              'style':
              'max-width: 420px; max-height: 580px; border-radius: 12px; overflow: hidden; position: relative;'
            },
          )
        else
          div(
            [
              button(
                [Component.text('close')],
                classes: 'modal-close-btn',
                attributes: const {
                  'style':
                  'position: absolute; top: 24px; right: 24px; border: none; background: rgba(255,255,255,0.9); border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold; z-index: 1000;'
                },
                events: {'click': (e) => setState(() => _showMakerModal = false)},
              ),
              MakerUploadForm(
                targetUserId: component.targetUserId,
                authState: component.authState,
                onBack: () => setState(() => _makerModalMode = 'options'),
                onUploadComplete: (shortcode) {
                  setState(() => _showMakerModal = false);
                  Router.of(context).replace('/$shortcode');
                },
              ),
            ],
            classes: 'upload-list-wrapper',
            attributes: const {
              'style':
              'width: 100%; max-width: 500px; max-height: 90vh; display: flex; flex-direction: column; gap: 16px; box-sizing: border-box; padding: 16px; position: relative; overflow-y: auto;'
            },
          )
      ],
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'
      },
    );
  }

  Component _buildDeleteConfirmModal() {
    return div(
      classes: 'global-modal-overlay',
      attributes: const {
        'style':
        'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 10000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'
      },
      [
        div(
          classes: 'white-sticker p-6',
          attributes: const {
            'style':
            'max-width: 400px; padding: 24px; border-radius: 12px; display: flex; flex-direction: column; gap: 16px; background: white; text-align: left; box-sizing: border-box;'
          },
          [
            h3([Component.text("Delete Folio?")],
                attributes: const {
                  'style':
                  'margin-top: 0; font-size: 18px; font-weight: bold; color: black;'
                }),
            p([
              Component.text(
                  "Are you sure you want to delete this folio forever? This will remove all associated pages and database configurations.")
            ],
                attributes: const {
                  'style':
                  'font-size: 13.5px; color: #555; line-height: 1.5; margin: 0;'
                }),
            div(
              attributes: const {
                'style':
                'display: flex; gap: 12px; justify-content: flex-end; margin-top: 8px;'
              },
              [
                button(
                  [Component.text("cancel")],
                  classes: 'profile-btn',
                  attributes: const {
                    'style':
                    'padding: 8px 16px; font-size: 12px; border: 1px solid #ddd; background: white; cursor: pointer; height: 32px;'
                  },
                  events: {
                    'click': (e) => setState(() {
                      _pendingDeleteId = null;
                      _pendingDeleteShortcode = null;
                    })
                  },
                ),
                button(
                  [Component.text("delete")],
                  classes: 'profile-btn',
                  attributes: const {
                    'style':
                    'padding: 8px 16px; font-size: 12px; border: 1px solid #ff5252; background: #ff5252; color: white; cursor: pointer; height: 32px;'
                  },
                  events: {
                    'click': (e) async {
                      final fid = _pendingDeleteId;
                      final sc = _pendingDeleteShortcode;
                      setState(() {
                        _pendingDeleteId = null;
                        _pendingDeleteShortcode = null;
                      });
                      if (fid != null) {
                        await fsDeleteDoc('fanzines/$fid');
                        if (sc != null && sc.isNotEmpty) {
                          await fsDeleteDoc('shortcodes/${sc.toUpperCase()}');
                        }
                      }
                    }
                  },
                )
              ],
            )
          ],
        )
      ],
    );
  }

  Component _buildWorksGridSchema(List<Map<String, dynamic>> works) {
    if (_loading) {
      return div(
        [p([Component.text('Loading maker assets...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    if (works.isEmpty) {
      return div(
        [
          span([Component.text('library_books')],
              classes: 'material-symbols-outlined text-gray-300',
              attributes: const {'style': 'font-size: 48px;'}),
          p([Component.text('No items available in this category.')],
              classes: 'text-sm text-gray italic mt-4',
              attributes: const {'style': 'margin-top: 16px;'}),
        ],
        classes: 'bg-white rounded-lg p-16 shadow-sm text-center',
      );
    }

    return div(
      [
        for (var w in works) _buildWorkGridTile(w),
      ],
      attributes: const {
        'style':
        'display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; width: 100%; box-sizing: border-box;'
      },
    );
  }

  Component _buildWorkGridTile(Map<String, dynamic> w) {
    final String fanzineId = w['id'] ?? '';
    final String title = w['title'] ?? 'Untitled Fanzine';
    final String volume = w['volume'] ?? '';
    final String issue = w['issue'] ?? '';
    final String wholeNumber = w['wholeNumber'] ?? '';
    final String shortCode = w['shortCode'] ?? '';

    String displaySuffix = '';
    if (volume.isNotEmpty) displaySuffix += " Vol. $volume";
    if (issue.isNotEmpty) displaySuffix += " No. $issue";
    if (wholeNumber.isNotEmpty) displaySuffix += " ($wholeNumber)";

    final String coverUrl = w['gridCoverImage'] ??
        (w['sourceFile'] != null
            ? 'https://placehold.co/450x720/png?text=Archival+Ingest'
            : 'https://placehold.co/450x720/png?text=Folio');

    final String codeKey = shortCode.isNotEmpty ? shortCode : fanzineId;

    final String draftWorkspace =
    (w['type'] == 'ingested') ? 'curator' : 'maker';
    final String targetHref =
    _showDrafts ? '/$codeKey/$draftWorkspace' : '/$codeKey';

    final cardData = Map<String, dynamic>.from(w);
    cardData['title'] = displaySuffix.isNotEmpty ? '$title$displaySuffix' : title;

    return FanzineThumbnailCard(
      fanzineData: cardData,
      targetHref: targetHref,
      customCoverUrl: coverUrl,
      cardType: 'fanzine',
      key: ValueKey('maker_card_${fanzineId}_${_showDrafts ? "draft" : "pub"}'),
      showIndicia: _showIndicia,
      onToggleShowIndicia: (val) {
        setState(() => _showIndicia = val);
      },
      onDelete: component.isMe
          ? (id, cardTitle) {
        setState(() {
          _pendingDeleteId = id;
          _pendingDeleteShortcode = shortCode;
        });
      }
          : null,
    );
  }

  @override
  Component build(BuildContext context) {
    if (!kIsWeb) {
      return div(
        [p([Component.text('Loading maker assets...')])],
        classes: 'p-16 text-center text-gray italic text-sm',
      );
    }

    return div(
      [
        div(
          [
            div(
              [
                if (component.isMe) ...[
                  button(
                    [Component.text("make")],
                    classes: 'profile-btn',
                    attributes: const {
                      'style':
                      'width: 100px; height: 28px; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: bold; text-align: center; border: 1px solid #ddd; border-radius: 0px !important; cursor: pointer; background: white;'
                    },
                    events: {
                      'click': (e) => setState(() {
                        _showMakerModal = true;
                        _makerModalMode = 'options';
                      })
                    },
                  ),
                  span([], attributes: const {'style': 'display: inline-block; width: 12px;'}),
                ],
                span(
                  [Component.text("published")],
                  classes: !_showDrafts
                      ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
                      : 'text-xs text-gray cursor-pointer',
                  events: {'click': (e) => _selectDraftMode(false)},
                ),
                if (component.canSeeDrafts) ...[
                  span([Component.text('|')],
                      classes: 'text-xs text-gray',
                      attributes: const {'style': 'display: inline-block; margin: 0 8px;'}),
                  span(
                    [Component.text("drafts")],
                    classes: _showDrafts
                        ? 'text-xs font-bold text-black border-b border-black cursor-pointer'
                        : 'text-xs text-gray cursor-pointer',
                    events: {'click': (e) => _selectDraftMode(true)},
                  ),
                ]
              ],
              attributes: const {
                'style':
                'display: flex; align-items: center; justify-content: center; width: 100%;'
              },
            )
          ],
          classes:
          'bg-white rounded-md p-4 shadow-sm flex-row items-center justify-center',
          attributes: const {
            'style':
            'display: flex; flex-wrap: wrap; gap: 12px; box-sizing: border-box; width: 100%; margin-bottom: 16px;'
          },
        ),
        _buildWorksGridSchema(_showDrafts ? _draftWorks : _publishedWorks),
        if (_showMakerModal) _buildMakerModalOverlay(),
        if (_pendingDeleteId != null) _buildDeleteConfirmModal(),
      ],
    );
  }
}