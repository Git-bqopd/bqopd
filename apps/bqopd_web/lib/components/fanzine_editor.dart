import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:bqopd_core/bqopd_core.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/web_utils.dart';
import '../utils/web_shortcode_service.dart';
import '../utils/unsaved_fanzine_registry.dart';
import '../components/fanzine_header.dart';
import '../repositories/repositories.dart';
import 'segmented_button.dart';

/// Refined workspace editor experience for the Jaspr web application.
/// Form-fitting, height-adaptive panel supporting dynamic folio adjustments.
class FanzineEditor extends StatefulComponent {
  final String frefFanzineId;
  final String? shortCode;
  final Map<String, dynamic>? fanzineData;
  final Map<String, Map<String, dynamic>> creatorProfiles;
  final Map<String, Map<String, dynamic>> imageStats;
  final List<Map<String, dynamic>> pageStructure;
  final AuthState? authState;
  final AuthBloc? authBloc;

  // State handlers to communicate reactive changes to parent layouts instantly
  final bool? twoPage;
  final void Function(bool)? onTwoPageChanged;

  const FanzineEditor({
    required this.frefFanzineId,
    this.shortCode,
    this.fanzineData,
    this.creatorProfiles = const {},
    this.imageStats = const {},
    this.pageStructure = const [],
    this.authState,
    this.authBloc,
    this.twoPage,
    this.onTwoPageChanged,
    super.key,
  });

  @override
  State<FanzineEditor> createState() => _FanzineEditorState();
}

class _FanzineEditorState extends State<FanzineEditor> {
  int _activeTab = 0; // 0: settings, 1: order, 2: upload

  // State Management Fields
  String _title = '';
  String _volume = '';
  String _issue = '';
  String _wholeNumber = '';
  bool _twoPage = true;
  bool _hasCover = true;
  bool _isSavingSettings = false;

  // Real-time Library Sync State
  dynamic _imagesUnsub;
  List<Map<String, dynamic>> _userImages = [];
  bool _loadingImages = true;
  bool _isUploading = false;

  // Library Orphan Modal State
  bool _showOrphanSelector = false;
  Set<String> _selectedOrphanIds = {};

  // Custom Confirmation Dialog State
  String? _activeConfirmId;
  bool _isConfirmDirect = false;
  String _confirmTitle = "";
  String _confirmBody = "";

  @override
  void initState() {
    super.initState();
    _syncMetadata();
    if (kIsWeb) {
      _listenToUserImages();
      onAuthStateChangedListener((uid, email) {
        _listenToUserImages();
      });
    }
  }

  @override
  void didUpdateComponent(FanzineEditor oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.fanzineData != component.fanzineData || oldComponent.twoPage != component.twoPage) {
      _syncMetadata();
    }
  }

  @override
  void dispose() {
    _imagesUnsub?.cancel();
    super.dispose();
  }

  void _syncMetadata() {
    final fd = component.fanzineData;
    if (fd != null) {
      _title = fd['title'] ?? '';
      _volume = fd['volume'] ?? '';
      _issue = fd['issue'] ?? '';
      _wholeNumber = fd['wholeNumber'] ?? '';
      _twoPage = component.twoPage ?? fd['twoPage'] ?? true; // Prioritize reactive parent state if present
      _hasCover = fd['hasCover'] ?? true;
    }
  }

  /// Establishes real-time connection to synchronized user media profiles.
  void _listenToUserImages() {
    _imagesUnsub?.cancel();
    _imagesUnsub = null;

    final uid = getCurrentUserId();
    if (uid == null) {
      if (mounted) {
        setState(() {
          _userImages = [];
          _loadingImages = false;
        });
      }
      return;
    }

    _imagesUnsub = fsListenQuery('images', 'uploaderId', '==', jsonEncode(uid), '', false, (String jsonStr) {
      try {
        final List decoded = jsonDecode(jsonStr) as List;
        final images = decoded.map((d) {
          final data = d['data'] as Map<String, dynamic>;
          data['id'] = d['id'];
          return data;
        }).toList();

        if (mounted) {
          setState(() {
            _userImages = images;
            _loadingImages = false;
          });
        }
      } catch (e) {
        print("Error parsing synchronized user images: $e");
      }
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final config = {
        'title': _title.trim(),
        'volume': _volume.trim(),
        'issue': _issue.trim(),
        'wholeNumber': _wholeNumber.trim(),
        'twoPage': _twoPage,
        'hasCover': _hasCover,
      };

      if (UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
        // COMMIT ENTIRE CONFIGURATION AND CHANNELS TO CLOUD FIRESTORE FOR FIRST TIME
        final fz = UnsavedFanzineRegistry.fanzines[component.frefFanzineId]!;

        final updatedFz = Fanzine(
          id: fz.id,
          title: _title.trim(),
          volume: _volume.trim(),
          issue: _issue.trim(),
          wholeNumber: _wholeNumber.trim(),
          type: fz.type,
          isLive: fz.isLive,
          processingStatus: fz.processingStatus,
          ownerId: fz.ownerId,
          editors: fz.editors,
          twoPage: _twoPage,
          hasCover: _hasCover,
          shortCode: fz.shortCode,
          sourceFile: fz.sourceFile,
          draftEntities: fz.draftEntities,
          masterCreators: fz.masterCreators,
          masterIndicia: fz.masterIndicia,
          indiciaPageId: fz.indiciaPageId,
          startMonth: fz.startMonth,
          startYear: fz.startYear,
          isSoftPublished: fz.isSoftPublished,
        );

        final fzDataToSave = {
          'title': updatedFz.title,
          'volume': updatedFz.volume,
          'issue': updatedFz.issue,
          'wholeNumber': updatedFz.wholeNumber,
          'type': updatedFz.type.name,
          'isLive': updatedFz.isLive,
          'processingStatus': updatedFz.processingStatus,
          'ownerId': updatedFz.ownerId,
          'editorId': updatedFz.ownerId,
          'editors': updatedFz.editors,
          'twoPage': updatedFz.twoPage,
          'hasCover': updatedFz.hasCover,
          'shortCode': updatedFz.shortCode,
          'shortCodeKey': updatedFz.shortCode?.toUpperCase(),
          'creationDate': WebFieldValue.serverTimestamp(),
        };

        // 1. Create master fanzine doc
        await fsSetDoc('fanzines/${component.frefFanzineId}', jsonEncode(fzDataToSave), true);

        // 2. Register shortcode master registry doc
        if (updatedFz.shortCode != null) {
          final scData = {
            'type': 'fanzine',
            'contentId': component.frefFanzineId,
            'displayCode': updatedFz.shortCode,
            'createdAt': WebFieldValue.serverTimestamp(),
          };
          await fsSetDoc('shortcodes/${updatedFz.shortCode!.toUpperCase()}', jsonEncode(scData), true);
        }

        // 3. Write nested page structures contiguously to subcollections
        final pages = UnsavedFanzineRegistry.pages[component.frefFanzineId] ?? [];
        for (var p in pages) {
          final pageData = {
            'imageId': p.imageId,
            'imageUrl': p.imageUrl,
            'pageNumber': p.pageNumber,
            'status': p.status,
            'spreadPosition': p.spreadPosition,
            'sidePreference': p.sidePreference,
            'width': p.width,
            'height': p.height,
            'createdAt': WebFieldValue.serverTimestamp(),
          };
          await fsSetDoc('fanzines/${component.frefFanzineId}/pages/${p.id}', jsonEncode(pageData), true);
        }

        // 4. Remove this fanzine from our temporary memory registry
        UnsavedFanzineRegistry.remove(component.frefFanzineId);

        // 5. Update local broad controllers to enforce smooth UX state transition
        UnsavedFanzineRegistry.getOrCreateFanzineController(component.frefFanzineId).add(updatedFz);
        UnsavedFanzineRegistry.getOrCreatePagesController(component.frefFanzineId).add(pages);

        print('[UNSAVED REGISTRY] Successfully committed temporary Fanzine: "${component.frefFanzineId}" to database.');
      } else {
        await fsUpdateDoc('fanzines/${component.frefFanzineId}', jsonEncode(config));
      }
    } catch (e) {
      print("Error saving fanzine settings: $e");
    } finally {
      setState(() => _isSavingSettings = false);
    }
  }

  Future<void> _deletePage(String pageId) async {
    try {
      if (UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
        final pages = UnsavedFanzineRegistry.pages[component.frefFanzineId] ?? [];
        final List<FanzinePage> updatedPages = [];
        int currentNum = 1;
        for (var p in pages) {
          if (p.id != pageId) {
            updatedPages.add(FanzinePage(
              id: p.id,
              pageNumber: currentNum++,
              imageId: p.imageId,
              imageUrl: p.imageUrl,
              gridUrl: p.gridUrl,
              listUrl: p.listUrl,
              storagePath: p.storagePath,
              status: p.status,
              templateId: p.templateId,
              spreadPosition: p.spreadPosition,
              sidePreference: p.sidePreference,
              width: p.width,
              height: p.height,
            ));
          }
        }
        UnsavedFanzineRegistry.pages[component.frefFanzineId] = updatedPages;
        UnsavedFanzineRegistry.getOrCreatePagesController(component.frefFanzineId).add(updatedPages);
        return;
      }

      // PERSISTED DATABASE DELETION WITH SEQUENTIAL HEALING
      await fsDeleteDoc('fanzines/${component.frefFanzineId}/pages/$pageId');

      // Filter out the deleted page and heal the rest sequentially
      final List<Map<String, dynamic>> fullPages = component.pageStructure
          .where((p) => _isPage5x8(p) && p['__id'] != pageId)
          .toList();

      final List<Future<void>> updates = [];
      for (int i = 0; i < fullPages.length; i++) {
        final item = fullPages[i];
        final String itemId = item['__id'] ?? '';
        final int currentNum = item['pageNumber'] ?? 0;
        final int expectedNum = i + 1;

        if (itemId.isNotEmpty && currentNum != expectedNum) {
          updates.add(
            fsUpdateDoc(
              'fanzines/${component.frefFanzineId}/pages/$itemId',
              jsonEncode({'pageNumber': expectedNum}),
            ),
          );
        }
      }
      if (updates.isNotEmpty) {
        await Future.wait(updates);
      }
    } catch (e) {
      print("Error removing page: $e");
    }
  }

  Future<void> _reorderPage(Map<String, dynamic> page, int delta) async {
    final String pageId = page['__id'] ?? '';
    if (pageId.isEmpty) return;

    try {
      if (UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
        final pages = UnsavedFanzineRegistry.pages[component.frefFanzineId] ?? [];
        final idx = pages.indexWhere((p) => p.id == pageId);
        if (idx == -1) return;

        final targetIdx = idx + delta;
        if (targetIdx < 0 || targetIdx >= pages.length) return;

        final updatedPages = List<FanzinePage>.from(pages);
        final temp = updatedPages[idx];
        updatedPages[idx] = updatedPages[targetIdx];
        updatedPages[targetIdx] = temp;

        for (int i = 0; i < updatedPages.length; i++) {
          final p = updatedPages[i];
          updatedPages[i] = FanzinePage(
            id: p.id,
            pageNumber: i + 1,
            imageId: p.imageId,
            imageUrl: p.imageUrl,
            gridUrl: p.gridUrl,
            listUrl: p.listUrl,
            storagePath: p.storagePath,
            status: p.status,
            templateId: p.templateId,
            spreadPosition: p.spreadPosition,
            sidePreference: p.sidePreference,
            width: p.width,
            height: p.height,
          );
        }
        UnsavedFanzineRegistry.pages[component.frefFanzineId] = updatedPages;
        UnsavedFanzineRegistry.getOrCreatePagesController(component.frefFanzineId).add(updatedPages);
        return;
      }

      // PERSISTED DATABASE REORDERING (SEQUENTIAL HEALING SWAP)
      final fullPages = component.pageStructure.where((p) => _isPage5x8(p)).toList();
      final idx = fullPages.indexWhere((p) => p['__id'] == pageId);
      if (idx == -1) return;

      final targetIdx = idx + delta;
      if (targetIdx < 0 || targetIdx >= fullPages.length) return;

      // Swapping elements in copy array of 5x8 pages
      final temp = fullPages[idx];
      fullPages[idx] = fullPages[targetIdx];
      fullPages[targetIdx] = temp;

      // Update and heal any indexing duplicates/drifts in parallel
      final List<Future<void>> updates = [];
      for (int i = 0; i < fullPages.length; i++) {
        final item = fullPages[i];
        final String itemId = item['__id'] ?? '';
        final int currentNum = item['pageNumber'] ?? 0;
        final int expectedNum = i + 1;

        if (itemId.isNotEmpty && currentNum != expectedNum) {
          updates.add(
            fsUpdateDoc(
              'fanzines/${component.frefFanzineId}/pages/$itemId',
              jsonEncode({'pageNumber': expectedNum}),
            ),
          );
        }
      }
      if (updates.isNotEmpty) {
        await Future.wait(updates);
      }
    } catch (e) {
      print("Error reordering: $e");
    }
  }

  Future<void> _updatePageLayout(Map<String, dynamic> page, String? spreadPosition, String sidePreference) async {
    final String pageId = page['__id'] ?? '';
    if (pageId.isEmpty) return;

    try {
      if (UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
        final pages = UnsavedFanzineRegistry.pages[component.frefFanzineId] ?? [];
        final idx = pages.indexWhere((p) => p.id == pageId);
        if (idx != -1) {
          final updatedPages = List<FanzinePage>.from(pages);
          final p = updatedPages[idx];
          updatedPages[idx] = FanzinePage(
            id: p.id,
            pageNumber: p.pageNumber,
            imageId: p.imageId,
            imageUrl: p.imageUrl,
            gridUrl: p.gridUrl,
            listUrl: p.listUrl,
            storagePath: p.storagePath,
            status: p.status,
            templateId: p.templateId,
            spreadPosition: spreadPosition,
            sidePreference: sidePreference,
            width: p.width,
            height: p.height,
          );
          UnsavedFanzineRegistry.pages[component.frefFanzineId] = updatedPages;
          UnsavedFanzineRegistry.getOrCreatePagesController(component.frefFanzineId).add(updatedPages);
        }
        return;
      }
      await fsUpdateDoc(
        'fanzines/${component.frefFanzineId}/pages/$pageId',
        jsonEncode({
          'spreadPosition': spreadPosition,
          'sidePreference': sidePreference,
        }),
      );
    } catch (e) {
      print("Error updating page layout: $e");
    }
  }

  bool _isImage5x8(Map<String, dynamic> img) {
    if (img['is5x8'] == true || img['type'] == 'template') return true;
    final w = img['width'] as num?;
    final h = img['height'] as num?;
    if (w == null || h == null || w == 0 || h == 0) {
      return true; // Fallback: default to true for unmeasured or uninitialized web assets
    }
    final ratio = w / h;
    return ratio >= 0.58 && ratio <= 0.67;
  }

  bool _isPage5x8(Map<String, dynamic> page) {
    if (page['templateId'] != null) return true;
    final w = page['width'] as num?;
    final h = page['height'] as num?;
    if (w == null || h == null || w == 0 || h == 0) {
      return true; // Fallback: default to true for unmeasured or uninitialized web assets
    }
    final ratio = w / h;
    return ratio >= 0.58 && ratio <= 0.67;
  }

  /// Triggers client native file browser completely within client Dart VM channels.
  void _triggerNewImageUpload() {
    triggerFilePicker('folio-editor-instant-picker', (base64, fileName, objectUrl) async {
      setState(() {
        _isUploading = true;
      });
      try {
        final dims = await getImageDimensions(objectUrl);
        final width = dims['width'] ?? 0;
        final height = dims['height'] ?? 0;
        final double ratio = (width > 0 && height > 0) ? width / height : 0.625;
        final bool is5x8 = (ratio >= 0.58 && ratio <= 0.67);

        final uid = getCurrentUserId();
        if (uid == null) throw Exception("User is not signed in.");

        final String path = 'uploads/$uid/folio_assets/${component.frefFanzineId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        final Uint8List bytes = base64Decode(base64);

        final downloadUrl = await stUpload(path, bytes, 'image/jpeg');
        final imageId = 'img_${DateTime.now().millisecondsSinceEpoch}';

        // Check vanity eligibility
        final String? email = component.authState?.user?.email;
        final bool useVanity = email != null && email.trim().toLowerCase() == 'kevin@712liberty.com';

        final shortCode = await WebShortcodeService.assignShortcode(
          contentType: 'image',
          contentId: imageId,
          isVanity: useVanity,
        ) ?? imageId.substring(imageId.length - 7).toUpperCase();

        final imgData = {
          'uid': uid,
          'uploaderId': uid,
          'fileUrl': downloadUrl,
          'fileName': fileName,
          'title': fileName,
          'status': 'approved',
          'tags': {},
          'indicia': '',
          'creators': [],
          'timestamp': WebFieldValue.serverTimestamp(),
          'shortCode': shortCode,
          'storagePath': path,
          'folioContext': component.frefFanzineId,
          'usedInFanzines': [component.frefFanzineId],
          'width': width,
          'height': height,
          'aspectRatio': ratio,
          'is5x8': is5x8,
        };

        // FIXED: Serialize imgData cleanly using jsonEncode instead of imgData.toString()
        await fsSetDoc('images/$imageId', jsonEncode(imgData), true);

        // Add to the folio pages immediately IF AND ONLY IF it matches the 5x8 page aspect ratio
        if (is5x8) {
          await _addExistingImage(imageId, downloadUrl, width, height);
        }

        print('[FOLIO UPLOAD] Image successfully processed.');
      } catch (e) {
        print('[FOLIO UPLOAD ERROR] $e');
      } finally {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });
        }
      }
    });
  }

  Future<void> _addExistingImage(String imageId, String imageUrl, int width, int height) async {
    final pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';
    if (UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
      final pages = UnsavedFanzineRegistry.pages[component.frefFanzineId] ?? [];
      final nextNum = pages.length + 1;
      final newPage = FanzinePage(
        id: pageId,
        pageNumber: nextNum,
        imageId: imageId,
        imageUrl: imageUrl,
        status: 'ready',
        width: width,
        height: height,
      );

      final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages)..add(newPage);
      UnsavedFanzineRegistry.pages[component.frefFanzineId] = updatedPages;
      UnsavedFanzineRegistry.getOrCreatePagesController(component.frefFanzineId).add(updatedPages);

      // FIXED: Associate the newly created page with this unsaved folio in the database
      // so it correctly propagates to the "FULL PAGES (5X8)" tab.
      await fsUpdateDoc('images/$imageId', jsonEncode({
        'usedInFanzines': WebFieldValue.arrayUnion([component.frefFanzineId])
      }));
      return;
    } else {
      final resStr = await fsQuery('fanzines/${component.frefFanzineId}/pages', '', '', '', '');
      final List pageDocs = jsonDecode(resStr) as List;
      final int nextNum = pageDocs.length + 1;

      await fsSetDoc('fanzines/${component.frefFanzineId}/pages/$pageId', jsonEncode({
        'imageId': imageId,
        'imageUrl': imageUrl,
        'pageNumber': nextNum,
        'status': 'ready',
        'width': width,
        'height': height,
        'createdAt': WebFieldValue.serverTimestamp(),
      }), true);

      await fsUpdateDoc('images/$imageId', jsonEncode({
        'usedInFanzines': WebFieldValue.arrayUnion([component.frefFanzineId])
      }));
    }
  }

  Future<void> _createNewTextPage() async {
    setState(() {
      _isUploading = true;
    });
    try {
      final IFanzineRepository repo = createFanzineRepository();

      final List<FanzinePage> allPages = component.pageStructure.map((p) {
        return FanzinePage.fromMap(p['__id'] ?? p['id'] ?? '', p);
      }).toList();

      final int lastPageNum = allPages.isNotEmpty ? allPages.length : 0;

      final initialText = """
# THE PUBLISHER
## New Custom Page Created

Start typing directly inside the text editor panel below to generate columns of printable markdown text.

{{IMAGE}}

* Enter bullet lists with an asterisk
* Customize headers with # or ##
""";

      await repo.insertPublisherPage(
        component.frefFanzineId,
        lastPageNum,
        initialText,
        allPages,
      );

      print('[FOLIO EDITOR] Text page created successfully.');
    } catch (e) {
      print('[FOLIO EDITOR ERROR] Failed to create text page: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _createNewCalendarPagePlaceholder() async {
    setState(() {
      _isUploading = true;
    });
    try {
      final String fanzineId = component.frefFanzineId;
      final int nextNum = component.pageStructure.length + 1;
      final String pageId = 'page_${DateTime.now().millisecondsSinceEpoch}';

      if (UnsavedFanzineRegistry.fanzines.containsKey(fanzineId)) {
        final pages = UnsavedFanzineRegistry.pages[fanzineId] ?? [];
        final newPage = FanzinePage(
          id: pageId,
          pageNumber: nextNum,
          status: 'ready',
          templateId: 'calendar_left',
        );
        final List<FanzinePage> updatedPages = List<FanzinePage>.from(pages)..add(newPage);
        UnsavedFanzineRegistry.pages[fanzineId] = updatedPages;
        UnsavedFanzineRegistry.getOrCreatePagesController(fanzineId).add(updatedPages);
      } else {
        await fsSetDoc('fanzines/$fanzineId/pages/$pageId', jsonEncode({
          'pageNumber': nextNum,
          'status': 'ready',
          'templateId': 'calendar_left',
          'createdAt': WebFieldValue.serverTimestamp(),
        }), true);
      }
      print('[FOLIO EDITOR] Calendar page placeholder created successfully.');
    } catch (e) {
      print('[FOLIO EDITOR ERROR] Failed to create calendar page: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _confirmRemoveImage(String imageId, bool isDirect) {
    final String actionText = isDirect ? "Delete Completely" : "Remove from Folio";
    final String bodyText = isDirect
        ? "This is a direct upload or publisher template page. Deleting it will remove it from ALL issues and your library forever."
        : "This image is from your library. Removing it will only take it out of this specific folio.";

    setState(() {
      _activeConfirmId = imageId;
      _isConfirmDirect = isDirect;
      _confirmTitle = actionText;
      _confirmBody = bodyText;
    });
  }

  Future<void> _executeImageRemoval() async {
    final imageId = _activeConfirmId;
    if (imageId == null) return;

    setState(() {
      _activeConfirmId = null;
      _isUploading = true;
    });

    try {
      if (_isConfirmDirect) {
        await fsDeleteDoc('images/$imageId');
      }

      // Find any page belonging to this image in current folio and delete it
      final pagesRes = await fsQuery('fanzines/${component.frefFanzineId}/pages', 'imageId', '==', jsonEncode(imageId), '');
      final List pageDocs = jsonDecode(pagesRes) as List;

      for (var pageDoc in pageDocs) {
        final pageId = pageDoc['id'] ?? '';
        if (pageId.isNotEmpty) {
          await _deletePage(pageId as String);
        }
      }

      print('[FOLIO REMOVE] Image/Page successfully removed/deleted.');
    } catch (e) {
      print('[FOLIO REMOVE ERROR] $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _addSelectedOrphans() async {
    if (_selectedOrphanIds.isEmpty) return;

    setState(() {
      _isUploading = true;
    });

    try {
      for (final imageId in _selectedOrphanIds) {
        final imgData = _userImages.firstWhere((img) => img['id'] == imageId);
        final String? url = imgData['fileUrl'] ?? imgData['gridUrl'];
        final int width = imgData['width'] ?? 0;
        final int height = imgData['height'] ?? 0;

        if (url != null) {
          if (_isImage5x8(imgData)) {
            await _addExistingImage(imageId, url, width, height);
          } else {
            // FIXED: Associate selected non-5x8 orphan assets with the folio so they correctly appear under "INLINE ASSETS"
            await fsUpdateDoc('images/$imageId', jsonEncode({
              'usedInFanzines': WebFieldValue.arrayUnion([component.frefFanzineId])
            }));
          }
        }
      }

      setState(() {
        _showOrphanSelector = false;
        _selectedOrphanIds.clear();
      });
    } catch (e) {
      print('[ORPHAN SELECTOR ERROR] $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _onSpreadPosChanged(Map<String, dynamic> page, int idx, int totalCount, List<Map<String, dynamic>> fullPages, String clickedVal) {
    final String currentSpreadPos = page['spreadPosition'] ?? '';

    if (clickedVal == 'start') {
      if (currentSpreadPos == 'start') {
        // Toggle OFF: disassemble both this and the next page
        _disassembleSpread(idx, idx + 1, fullPages, 'either', 'either');
      } else {
        // Toggle ON: must not be the last image
        if (idx < totalCount - 1) {
          _assembleSpread(idx, idx + 1, fullPages);
        }
      }
    } else if (clickedVal == 'end') {
      if (currentSpreadPos == 'end') {
        // Toggle OFF: disassemble both this and the previous page
        _disassembleSpread(idx, idx - 1, fullPages, 'either', 'either');
      } else {
        // Toggle ON: must not be the first image
        if (idx > 0) {
          _assembleSpread(idx - 1, idx, fullPages);
        }
      }
    }
  }

  void _onSidePrefChanged(Map<String, dynamic> page, int idx, int totalCount, List<Map<String, dynamic>> fullPages, String clickedVal) {
    final String currentSpreadPos = page['spreadPosition'] ?? '';

    if (currentSpreadPos == 'start') {
      if (clickedVal != 'left') {
        // Spread is broken: disassembled both this and the next page
        _disassembleSpread(idx, idx + 1, fullPages, clickedVal, 'either');
      } else {
        _updatePageLayout(page, 'start', 'left');
      }
    } else if (currentSpreadPos == 'end') {
      if (clickedVal != 'right') {
        // Spread is broken: disassembled both this and the previous page
        _disassembleSpread(idx, idx - 1, fullPages, clickedVal, 'either');
      } else {
        _updatePageLayout(page, 'end', 'right');
      }
    } else {
      // Independent preference change
      _updatePageLayout(page, null, clickedVal);
    }
  }

  void _assembleSpread(int startIdx, int endIdx, List<Map<String, dynamic>> fullPages) {
    if (startIdx < 0 || endIdx >= fullPages.length) return;
    final startPage = fullPages[startIdx];
    final endPage = fullPages[endIdx];

    _updatePageLayout(startPage, 'start', 'left');
    _updatePageLayout(endPage, 'end', 'right');
  }

  void _disassembleSpread(int activeIdx, int siblingIdx, List<Map<String, dynamic>> fullPages, String activeTargetSide, String siblingTargetSide) {
    final activePage = fullPages[activeIdx];
    _updatePageLayout(activePage, null, activeTargetSide);

    if (siblingIdx >= 0 && siblingIdx < fullPages.length) {
      final siblingPage = fullPages[siblingIdx];
      _updatePageLayout(siblingPage, null, siblingTargetSide);
    }
  }

  Component _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return span(
      classes: 'text-xs cursor-pointer ${isActive ? 'font-bold' : 'text-gray'}',
      events: {'click': (e) => setState(() => _activeTab = index)},
      [text(label)],
    );
  }

  Component _buildSettingsTab() {
    // Preserve upper/lower-case vanity layout: convert to UPPERCASE first, then map the BQOPD string to lowercase.
    final String currentShortcode = component.shortCode != null
        ? component.shortCode!.toUpperCase().replaceAll('BQOPD', 'bqopd')
        : 'pending...';

    return div([
      // Row 1: Shortcode rendered cleanly inline with metadata
      div(
        [text('shortcode: $currentShortcode')],
        classes: 'text-xs text-gray-500 font-semibold mb-1 text-left',
      ),

      // Row 2: new folio name input
      div([
        input(
          attributes: {'type': 'text', 'placeholder': 'new folio name', 'value': _title},
          events: {'input': (e) => _title = getInputValue(e)},
        )
      ], classes: 'flex-col mb-1'),

      // Row 3: volume, issue, wholeNumber inputs (vol. / num. / whole num.)
      div([
        div([
          input(
            attributes: {'type': 'text', 'placeholder': 'vol.', 'value': _volume},
            events: {'input': (e) => _volume = getInputValue(e)},
          )
        ], classes: 'flex-1 flex-col'),
        div([
          input(
            attributes: {'type': 'text', 'placeholder': 'num.', 'value': _issue},
            events: {'input': (e) => _issue = getInputValue(e)},
          )
        ], classes: 'flex-1 flex-col'),
        div([
          input(
            attributes: {'type': 'text', 'placeholder': 'whole num.', 'value': _wholeNumber},
            events: {'input': (e) => _wholeNumber = getInputValue(e)},
          )
        ], classes: 'flex-1 flex-col'),
      ], classes: 'flex-row gap-2 mb-1', attributes: const {'style': 'display: flex; gap: 8px;'}),

      // Row 4: Custom M3 Switch for two page layout
      div(
        [
          span([
            text(_twoPage ? 'two page spread (switch: single page view)' : 'single page view (switch: two page spread)')
          ], classes: 'text-xs font-medium', attributes: const {'style': 'color: #4a4a4a;'}),
          _buildCustomToggleSwitch(_twoPage)
        ],
        classes: 'flex-row items-center justify-between cursor-pointer',
        attributes: const {
          'style': 'padding: 10px 12px; background-color: #f9f9f9; border: 1px solid #eee; border-radius: 8px; margin-bottom: 4px; display: flex; align-items: center; justify-content: space-between;'
        },
        events: {
          'click': (e) {
            final nextValue = !_twoPage;
            setState(() => _twoPage = nextValue);
            if (component.onTwoPageChanged != null) {
              component.onTwoPageChanged!(nextValue);
            }
          }
        },
      ),

      // Row 5: Save configuration button
      button(
        [text(_isSavingSettings ? 'saving folio...' : 'save folio')],
        classes: 'btn-primary w-full',
        attributes: _isSavingSettings ? {'disabled': 'true'} : const {},
        events: {'click': (e) => _saveSettings()},
      )
    ], classes: 'flex-col text-left p-2', attributes: const {'style': 'gap: 8px; display: flex;'});
  }

  Component _buildCustomToggleSwitch(bool val) {
    return div(
      [],
      attributes: {
        'style': 'width: 44px; height: 24px; border-radius: 12px; background-color: ${val ? '#808080' : '#ccc'}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }

  Component _buildCustomToggleSwitchForCover(bool val) {
    return div(
      [],
      attributes: {
        'style': 'width: 33px; height: 18px; border-radius: 10px; background-color: ${val ? '#808080' : '#ccc'}; position: relative; transition: background-color 0.2s; cursor: pointer; display: inline-block;'
      },
    );
  }

  Component _buildOrderTab() {
    final fullPages = component.pageStructure.where((p) => _isPage5x8(p)).toList();

    if (fullPages.isEmpty) {
      return div([
        span([text('format_list_numbered')], classes: 'material-symbols-outlined text-gray-300', attributes: const {'style': 'font-size: 48px;'}),
        p([text('No pages added to zine flatplan yet.')])
      ], classes: 'p-16 text-center text-gray italic');
    }

    return div([
      h2(
        [text('Folio Flatplan Sequence')],
        classes: 'text-sm font-bold text-gray uppercase tracking-wider mb-3',
      ),

      for (int i = 0; i < fullPages.length; i++)
        _buildOrderPageRow(fullPages[i], i, fullPages.length, fullPages)
    ], classes: 'flex-col gap-3 text-left p-2');
  }

  Component _buildOrderPageRow(Map<String, dynamic> page, int idx, int totalCount, List<Map<String, dynamic>> fullPages) {
    final String? optimalUrl = page['gridUrl'] ?? page['listUrl'] ?? page['imageUrl'];
    final bool isPending = optimalUrl == null || optimalUrl.isEmpty;
    final String? templateId = page['templateId'];

    final String selectedSpreadPos = page['spreadPosition'] ?? '';
    final String selectedSidePref = page['sidePreference'] ?? 'either';

    final bool isPage1Cover = idx == 0 && _hasCover;

    // Local variables are explicitly declared as Component to align with web target architecture
    Component? layoutButtonsComponent;
    if (!isPage1Cover) {
      layoutButtonsComponent = SegmentedButton<String>(
        segments: const ['start', 'end'],
        selected: selectedSpreadPos,
        labelBuilder: (val) => val,
        onSelectionChanged: (val) {
          _onSpreadPosChanged(page, idx, totalCount, fullPages, val);
        },
      );
    } else {
      layoutButtonsComponent = div([], attributes: const {'style': 'width: 140px;'});
    }

    Component sidePreferenceComponent = SegmentedButton<String>(
      segments: const ['left', 'either', 'right'],
      selected: isPage1Cover ? 'right' : selectedSidePref,
      labelBuilder: (val) => val,
      onSelectionChanged: (val) {
        if (isPage1Cover) return;
        _onSidePrefChanged(page, idx, totalCount, fullPages, val);
      },
    );

    Component? coverSwitchComponent;
    if (idx == 0) {
      coverSwitchComponent = div(
        [
          span([text('cover')], attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #49454F; margin-right: 6px;'}),
          _buildCustomToggleSwitchForCover(_hasCover),
        ],
        attributes: const {
          'style': 'display: inline-flex; align-items: center; margin-left: auto;'
        },
        events: {
          'click': (e) {
            final nextVal = !_hasCover;
            setState(() => _hasCover = nextVal);

            // Synchronously update the first page layout fields to align with the cover's active status
            if (nextVal) {
              _updatePageLayout(page, null, 'right');
            } else {
              _updatePageLayout(page, null, 'either');
            }

            if (!UnsavedFanzineRegistry.fanzines.containsKey(component.frefFanzineId)) {
              fsUpdateDoc('fanzines/${component.frefFanzineId}', jsonEncode({'hasCover': nextVal}));
            }
          }
        },
      );
    } else {
      coverSwitchComponent = div([]);
    }

    return div(
      classes: 'fanzine-page-row-card',
      attributes: const {
        'style': 'display: flex; flex-direction: column; gap: 12px; border: 1px solid #d1d5db; border-radius: 8px; padding: 16px; background-color: #ffffff; margin-bottom: 16px; box-shadow: 0 1px 2px rgba(0,0,0,0.05);'
      },
      [
        // Top Row: Thumbnail, Page Number, Title, reordering buttons
        div(
            classes: 'flex-row items-center justify-between',
            attributes: const {
              'style': 'display: flex; flex-direction: row; justify-content: space-between; align-items: center; width: 100%;'
            },
            [
              div([
                span(
                  [text('${idx + 1}.')], // Use absolute visual loop index instead of database metadata pageNum
                  classes: 'font-black text-xs text-gray-400',
                  attributes: const {'style': 'width: 20px; text-align: right; margin-right: 8px; display: inline-block;'},
                ),
                div(
                  [
                    if (templateId == 'basic_text')
                      div([
                        span([text('description')], classes: 'material-symbols-outlined', attributes: const {
                          'style': 'font-size: 16px; color: #6750A4;'
                        })
                      ], classes: 'w-full h-full flex items-center justify-center')
                    else if (templateId == 'calendar_left' || templateId == 'calendar_right')
                      div([
                        span([text('calendar_today')], classes: 'material-symbols-outlined', attributes: const {
                          'style': 'font-size: 16px; color: #6750A4;'
                        })
                      ], classes: 'w-full h-full flex items-center justify-center')
                    else if (!isPending)
                        img(
                            src: optimalUrl!,
                            attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'}
                        )
                      else
                        div(
                          [
                            span(
                              [text('progress_activity')],
                              classes: 'material-symbols-outlined text-gray-300',
                              attributes: const {'style': 'font-size: 16px;'},
                            )
                          ],
                          classes: 'shimmer-bg w-full h-full flex items-center justify-center',
                        )
                  ],
                  classes: 'rounded border border-gray-200 overflow-hidden bg-white',
                  attributes: const {'style': 'width: 36px; height: 50px; position: relative; display: inline-block; vertical-align: middle; margin-right: 12px;'},
                ),
                span(
                  [
                    text(templateId == 'basic_text'
                        ? 'Generated Text Page'
                        : (templateId != null && templateId.startsWith('calendar')
                        ? 'Generated Calendar Page'
                        : (isPending ? 'Processing web asset...' : 'Archival Page')))
                  ],
                  classes: 'text-xs font-bold text-gray-700',
                  attributes: const {'style': 'display: inline-block; vertical-align: middle;'},
                )
              ], classes: 'flex-row items-center gap-3', attributes: const {'style': 'display: flex; align-items: center;'}),

              // Action Arrow reordering
              div([
                button(
                  [span([text('arrow_upward')], classes: 'material-symbols-outlined text-sm')],
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: (idx == 0) ? {'disabled': 'true'} : const {}, // Disable up arrow strictly at first visual index
                  events: {'click': (e) => _reorderPage(page, -1)},
                ),
                button(
                  [span([text('arrow_downward')], classes: 'material-symbols-outlined text-sm')],
                  classes: 'p-1 hover:bg-gray-100 rounded border-none bg-transparent cursor-pointer',
                  attributes: (idx >= totalCount - 1) ? {'disabled': 'true'} : const {}, // Disable down arrow strictly at final visual index
                  events: {'click': (e) => _reorderPage(page, 1)},
                ),
                span([text('|')], classes: 'px-1 text-gray-300', attributes: const {'style': 'margin: 0 4px;'}),
                button(
                  [span([text('close')], classes: 'material-symbols-outlined text-sm text-red-500')],
                  classes: 'p-1 hover:bg-red-50 rounded border-none bg-transparent cursor-pointer',
                  events: {'click': (e) => _deletePage(page['__id'] ?? '')},
                ),
              ], classes: 'flex-row items-center gap-1', attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'}
              )
            ]
        ),

        // Bottom Row: Aligned columns for Segmented Buttons and Cover switch
        div(
          classes: 'flex-row flex-wrap justify-between items-center pt-3 border-t border-gray-100',
          attributes: const {
            'style': 'display: flex; flex-direction: row; flex-wrap: wrap; justify-content: flex-start; align-items: center; gap: 16px; border-top: 1px solid #f3f4f6; width: 100%;'
          },
          [
            // Column 1: Spread Position (start | end)
            div(
                attributes: const {
                  'style': 'width: 140px; display: flex; align-items: center;'
                },
                [layoutButtonsComponent]
            ),

            // Column 2: Side Preference (left | either | right)
            div(
                attributes: const {
                  'style': 'width: 200px; display: flex; align-items: center;'
                },
                [sidePreferenceComponent]
            ),

            // Column 3: Cover Switch (only for the first page)
            coverSwitchComponent,
          ],
        )
      ],
    );
  }

  Component _buildUploadTab() {
    // Filter user's images that belong to this fanzine
    final folioImages = _userImages.where((img) {
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? context = img['folioContext'];
      return context == component.frefFanzineId || usedIn.contains(component.frefFanzineId);
    }).toList();

    // 1. Stable sort to keep shortnames consistent and global
    folioImages.sort((a, b) {
      final aT = a['timestamp'] ?? a['createdAt'] ?? '';
      final bT = b['timestamp'] ?? b['createdAt'] ?? '';
      return aT.toString().compareTo(bT.toString());
    });

    final Map<String, String> imageShortNames = {};
    for (int i = 0; i < folioImages.length; i++) {
      final String id = folioImages[i]['id'] ?? '';
      if (id.isNotEmpty) {
        imageShortNames[id] = "img${(i + 1).toString().padLeft(2, '0')}";
      }
    }

    final fiveByEightDocs = folioImages.where((img) => _isImage5x8(img)).toList();
    final otherDocs = folioImages.where((img) => !_isImage5x8(img)).toList();

    return div([
      // 1. Primary actions row
      div(
        [
          button(
              [
                if (_isUploading)
                  span([text('progress_activity')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px; animation: spin 1s linear infinite;'})
                else
                  span([text('upload')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                text(_isUploading ? "uploading..." : "upload new image")
              ],
              attributes: {
                'style': 'background-color: #9e9e9e; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                if (_isUploading) 'disabled': 'true'
              },
              events: {
                'click': (e) {
                  if (!_isUploading) _triggerNewImageUpload();
                }
              }
          ),
          button(
              [
                span([text('photo_library')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                text("select orphan image")
              ],
              attributes: {
                'style': 'background-color: #9e9e9e; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                if (_isUploading) 'disabled': 'true'
              },
              events: {
                'click': (e) {
                  if (!_isUploading) setState(() => _showOrphanSelector = true);
                }
              }
          ),
        ],
        attributes: const {
          'style': 'display: flex; gap: 12px; justify-content: center; width: 100%; margin-top: 8px; margin-bottom: 12px;'
        },
      ),

      // 2. Custom Publisher generation buttons row
      div(
        [
          button(
              [
                span([text('note_add')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                text("new text page")
              ],
              attributes: {
                'style': 'background-color: #7e57c2; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                if (_isUploading) 'disabled': 'true'
              },
              events: {
                'click': (e) {
                  if (!_isUploading) _createNewTextPage();
                }
              }
          ),
          button(
              [
                span([text('calendar_today')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 18px; margin-right: 6px;'}),
                text("new calendar page")
              ],
              attributes: {
                'style': 'background-color: #7e57c2; color: white; border-radius: 20px; border: none; padding: 10px 18px; font-size: 11px; font-weight: bold; cursor: pointer; display: flex; align-items: center; justify-content: center;',
                if (_isUploading) 'disabled': 'true'
              },
              events: {
                'click': (e) {
                  if (!_isUploading) _createNewCalendarPagePlaceholder();
                }
              }
          ),
        ],
        attributes: const {
          'style': 'display: flex; gap: 12px; justify-content: center; width: 100%; margin-top: 0px; margin-bottom: 20px;'
        },
      ),

      // Subtle animated progress indicator directly below buttons
      if (_isUploading)
        div([
          div([], attributes: const {
            'style': 'height: 3px; background-color: #6750A4; width: 60%; border-radius: 2px; animation: shimmerKeyframe 1.5s infinite linear;'
          })
        ], attributes: const {
          'style': 'width: 100%; height: 3px; background-color: #eee; border-radius: 2px; overflow: hidden; margin-top: -12px; margin-bottom: 16px;'
        }),

      // If empty and not currently uploading, show empty placeholder
      if (folioImages.isEmpty && !_isUploading)
        div(
          [text("no images in this folio yet.")],
          attributes: const {
            'style': 'text-align: center; padding: 40px 16px; color: #888; font-size: 13px; font-style: italic; width: 100%; border-top: 1px solid #f0f0f0;'
          },
        )
      else ...[
        // Categorized Grids
        if (fiveByEightDocs.isNotEmpty || (_isUploading && fiveByEightDocs.isEmpty && otherDocs.isEmpty)) ...[
          div([
            span(
              [text("full pages (5x8)")],
              attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'},
            )
          ], attributes: const {'style': 'margin-top: 12px; margin-bottom: 8px;'}),
          _buildUploadedImagesGrid(fiveByEightDocs, imageShortNames, showUploadPlaceholder: _isUploading),
          div([], attributes: const {'style': 'height: 16px;'})
        ],

        if (otherDocs.isNotEmpty && !(_isUploading && fiveByEightDocs.isEmpty && otherDocs.isEmpty)) ...[
          div([
            span(
              [text("inline assets")],
              attributes: const {'style': 'font-size: 11px; font-weight: bold; color: #666; text-transform: uppercase; letter-spacing: 0.5px;'},
            )
          ], attributes: const {'style': 'margin-top: 12px; margin-bottom: 8px;'}),
          _buildUploadedImagesGrid(otherDocs, imageShortNames),
          div([], attributes: const {'style': 'height: 16px;'})
        ]
      ]
    ], classes: 'flex-col gap-3 text-left p-2');
  }

  Component _buildUploadedImagesGrid(List<Map<String, dynamic>> docs, Map<String, String> imageShortNames, {bool showUploadPlaceholder = false}) {
    return div(
      [
        if (showUploadPlaceholder)
          _buildShimmerPlaceholderCard(),
        for (var doc in docs)
          _buildFolioGridItem(doc, imageShortNames)
      ],
      attributes: const {
        'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 10px; width: 100%; margin-top: 8px;'
      },
    );
  }

  Component _buildShimmerPlaceholderCard() {
    return div(
        [
          div([
            span([text('progress_activity')], classes: 'material-symbols-outlined', attributes: const {
              'style': 'font-size: 24px; color: #6750A4; animation: spin 1s linear infinite;'
            }),
            span([text("processing...")], attributes: const {
              'style': 'font-size: 9px; color: #6750A4; font-weight: bold; margin-top: 8px;'
            })
          ], attributes: const {
            'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%;'
          })
        ],
        classes: 'shimmer-bg',
        attributes: const {
          'style': 'aspect-ratio: 5 / 8; background-color: #f5f5f5; border: 1px solid rgba(103, 80, 164, 0.3); border-radius: 6px; position: relative; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.05);'
        }
    );
  }

  Component _buildFolioGridItem(Map<String, dynamic> doc, Map<String, String> imageShortNames) {
    final String imageId = doc['id'] ?? '';
    final String? optimalUrl = doc['gridUrl'] ?? doc['fileUrl'];
    final String title = doc['title'] ?? doc['fileName'] ?? 'untitled';
    final int width = doc['width'] ?? 0;
    final int height = doc['height'] ?? 0;
    final bool isDirect = doc['folioContext'] == component.frefFanzineId;
    final bool isTemplate = doc['isGenerated'] == true || doc['type'] == 'template';
    final String shortName = imageShortNames[imageId] ?? '';

    return div(
      [
        // Background Image or Template icon preview
        if (isTemplate)
          div([
            span([text('description')], classes: 'material-symbols-outlined', attributes: const {
              'style': 'font-size: 40px; color: #6750A4;'
            }),
            span([text('Generated Page')], attributes: const {
              'style': 'font-size: 8px; font-weight: bold; color: #6750A4; margin-top: 4px;'
            })
          ], attributes: const {
            'style': 'display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; background: #ffffff;'
          })
        else if (optimalUrl != null && optimalUrl.isNotEmpty)
          img(
              src: optimalUrl,
              attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'}
          )
        else
          div([text("no preview")], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; height: 100%; color: #aaa; font-size: 11px;'}),

        // Dimensions and badges (Absolute Positioned)
        div(
          [
            div(
              [text(isDirect ? "direct" : "added")],
              attributes: const {
                'style': 'background-color: rgba(33,33,33,0.75); color: white; font-size: 8px; font-weight: bold; border-radius: 4px; padding: 2px 4px; text-align: center; text-transform: lowercase; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
              },
            ),
            div(
              [text("${width}x${height}")],
              attributes: const {
                'style': 'background-color: rgba(0,0,0,0.65); color: white; font-size: 8px; font-weight: bold; border-radius: 4px; padding: 2px 4px; text-align: center;'
              },
            )
          ],
          attributes: const {
            'style': 'position: absolute; top: 4px; left: 4px; right: 4px; display: flex; flex-direction: column; gap: 2px; pointer-events: none;'
          },
        ),

        // Remove/Delete Action Button on Top-Right (Absolute Positioned)
        div(
          [
            button(
                [span([text(isDirect || isTemplate ? 'delete' : 'close')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 14px;'})],
                attributes: {
                  'style': 'border: none; background: rgba(0,0,0,0.7); border-radius: 50%; width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; cursor: pointer; color: ${isDirect || isTemplate ? '#ff5252' : 'white'}; border: 1px solid white;'
                },
                events: {
                  'click': (e) {
                    _confirmRemoveImage(imageId, isDirect || isTemplate);
                  }
                }
            )
          ],
          attributes: const {
            'style': 'position: absolute; top: 4px; right: 4px;'
          },
        ),

        // Footer Title (Absolute Positioned) with dynamic fanzine-level shortname badge layered just above the filename text
        div(
          [
            if (shortName.isNotEmpty)
              div(
                  [text(shortName)],
                  attributes: const {
                    'style': 'background-color: #6750A4; color: white; font-size: 8px; font-weight: bold; border-radius: 4px; padding: 1px 4px; display: inline-block; margin-bottom: 3px; text-transform: lowercase; letter-spacing: 0.5px;'
                  }
              ),
            span(
              [text(title.toLowerCase())],
              attributes: const {
                'style': 'font-size: 8px; color: white; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block; text-align: center;'
              },
            )
          ],
          attributes: const {
            'style': 'position: absolute; bottom: 0; left: 0; right: 0; background-color: rgba(0,0,0,0.65); padding: 4px 6px; pointer-events: none; text-align: center; display: flex; flex-direction: column; align-items: center;'
          },
        )
      ],
      attributes: const {
        'style': 'aspect-ratio: 5 / 8; background-color: #f5f5f5; border: 1px solid rgba(0,0,0,0.1); border-radius: 6px; position: relative; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.05);'
      },
    );
  }

  Component _buildOrphanSelectorModal() {
    // Filter user's images that are not yet in this fanzine
    final orphanImages = _userImages.where((img) {
      final List usedIn = img['usedInFanzines'] ?? [];
      final String? context = img['folioContext'];
      return context != component.frefFanzineId && !usedIn.contains(component.frefFanzineId);
    }).toList();

    return div(
      [
        div(
          [
            // Modal Header
            div(
              [
                h2(
                  [text("Select Orphan Images to Add (${_selectedOrphanIds.length})")],
                  attributes: const {'style': 'font-size: 16px; font-weight: bold; margin: 0; color: black;'},
                ),
                div(
                  [
                    if (_selectedOrphanIds.isNotEmpty)
                      button(
                          [text("add selected")],
                          attributes: const {
                            'style': 'background-color: #6750A4; color: white; border: none; border-radius: 20px; padding: 6px 14px; font-size: 11px; font-weight: bold; cursor: pointer;'
                          },
                          events: {
                            'click': (e) => _addSelectedOrphans()
                          }
                      ),
                    button(
                        [text("×")],
                        attributes: const {
                          'style': 'border: none; background: #eee; border-radius: 50%; width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold;'
                        },
                        events: {
                          'click': (e) {
                            setState(() {
                              _showOrphanSelector = false;
                              _selectedOrphanIds.clear();
                            });
                          }
                        }
                    )
                  ],
                  attributes: const {'style': 'display: flex; gap: 8px; align-items: center;'},
                )
              ],
              attributes: const {
                'style': 'padding: 16px 20px; border-bottom: 1px solid #eee; display: flex; align-items: center; justify-content: space-between;'
              },
            ),

            // Modal Body
            div(
              [
                if (_loadingImages)
                  div([text("Loading gallery...")], attributes: const {'style': 'text-align: center; padding: 40px 0; color: #888;'})
                else if (orphanImages.isEmpty)
                  div(
                    [
                      span([text('image_not_supported')], classes: 'material-symbols-outlined', attributes: const {'style': 'font-size: 48px; color: #ccc;'}),
                      p([text("No orphan images available in your library.")], attributes: const {'style': 'font-size: 13px; font-style: italic; margin-top: 8px;'})
                    ],
                    attributes: const {'style': 'text-align: center; padding: 40px 0; color: #888;'},
                  )
                else
                  div(
                    [
                      for (var img in orphanImages)
                        _buildOrphanGridItem(img)
                    ],
                    attributes: const {
                      'style': 'display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 150px)); gap: 12px;'
                    },
                  )
              ],
              attributes: const {
                'style': 'padding: 20px; overflow-y: auto; flex: 1;'
              },
            )
          ],
          attributes: const {
            'style': 'background-color: white; border-radius: 12px; width: 100%; max-width: 600px; max-height: 80vh; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 10px 25px rgba(0,0,0,0.2); text-align: left;'
          },
        )
      ],
      classes: 'global-modal-overlay',
      attributes: const {
        'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 20000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(6px);'
      },
    );
  }

  Component _buildOrphanGridItem(Map<String, dynamic> imgData) {
    final String imageId = imgData['id'] ?? '';
    final bool isSelected = _selectedOrphanIds.contains(imageId);
    final String? thumbUrl = imgData['gridUrl'] ?? imgData['fileUrl'];

    return div(
      [
        if (thumbUrl != null && thumbUrl.isNotEmpty)
          img(
              src: thumbUrl,
              attributes: const {'style': 'width: 100%; height: 100%; object-fit: cover;'}
          )
        else
          div([text("no preview")], attributes: const {'style': 'display: flex; align-items: center; justify-content: center; height: 100%; color: #aaa; font-size: 11px;'}),

        // Checkmark badge
        if (isSelected)
          div(
            [
              span(
                [text('check')],
                classes: 'material-symbols-outlined',
                attributes: const {'style': 'font-size: 12px; color: white; font-weight: bold;'},
              )
            ],
            attributes: const {
              'style': 'position: absolute; top: 6px; right: 6px; background-color: #6750A4; border-radius: 50%; width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);'
            },
          )
      ],
      attributes: {
        'style': 'aspect-ratio: 5/8; background-color: #f5f5f5; border-radius: 6px; overflow: hidden; border: 2px solid ${isSelected ? '#6750A4' : 'transparent'}; position: relative; cursor: pointer; box-shadow: 0 1px 3px rgba(0,0,0,0.1);'
      },
      events: {
        'click': (e) {
          setState(() {
            if (isSelected) {
              _selectedOrphanIds.remove(imageId);
            } else {
              _selectedOrphanIds.add(imageId);
            }
          });
        }
      },
    );
  }

  Component _buildConfirmModal() {
    return div(
      [
        div(
          [
            h3([text(_confirmTitle)], attributes: const {'style': 'font-size: 16px; font-weight: bold; margin: 0; color: black;'}),
            p([text(_confirmBody)], attributes: const {'style': 'font-size: 13px; color: #555; line-height: 1.5; margin: 0;'}),
            div(
              [
                button(
                    [text("cancel")],
                    attributes: const {
                      'style': 'background-color: #eee; color: black; border: none; border-radius: 8px; padding: 8px 16px; font-size: 12px; font-weight: bold; cursor: pointer;'
                    },
                    events: {
                      'click': (e) {
                        setState(() {
                          _activeConfirmId = null;
                        });
                      }
                    }
                ),
                button(
                    [text(_isConfirmDirect ? "DELETE FOREVER" : "REMOVE")],
                    attributes: {
                      'style': 'background-color: ${_isConfirmDirect ? "#ff5252" : "#6750A4"}; color: white; border: none; border-radius: 8px; padding: 8px 16px; font-size: 12px; font-weight: bold; cursor: pointer;'
                    },
                    events: {
                      'click': (e) => _executeImageRemoval()
                    }
                )
              ],
              attributes: const {'style': 'display: flex; gap: 12px; justify-content: flex-end; margin-top: 8px;'},
            )
          ],
          attributes: const {
            'style': 'background-color: white; border-radius: 12px; width: 100%; max-width: 400px; padding: 24px; display: flex; flex-direction: column; gap: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); text-align: left;'
          },
        )
      ],
      classes: 'global-modal-overlay',
      attributes: const {
        'style': 'position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.65); z-index: 30000; display: flex; align-items: center; justify-content: center; backdrop-filter: blur(4px);'
      },
    );
  }

  @override
  Component build(BuildContext context) {
    return div([
      // 1. Core Tab Row
      div([
        _buildTabButton('settings', 0),
        span([text('|')], classes: 'px-4 text-gray text-xs'),
        _buildTabButton('order', 1),
        span([text('|')], classes: 'px-4 text-gray text-xs'),
        _buildTabButton('upload', 2),
      ], classes: 'flex-row justify-center items-center py-2 bg-gray-100'),

      // 2. Active Tab Sheet - Height Auto adaptive
      div([
        if (_activeTab == 0) _buildSettingsTab(),
        if (_activeTab == 1) _buildOrderTab(),
        if (_activeTab == 2) _buildUploadTab(),
      ], classes: 'flex-col p-4'),

      if (_showOrphanSelector) _buildOrphanSelectorModal(),
      if (_activeConfirmId != null) _buildConfirmModal(),
    ], classes: 'white-sticker-flexible w-full mt-2');
  }
}