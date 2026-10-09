import 'dart:async';
import 'dart:convert';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import '../utils/web_firebase_interop.dart';
import '../utils/firebase_mocks.dart';
import '../utils/unsaved_fanzine_registry.dart';

/// Data model holding all publication and transcription metadata for a historical letter.
class HistoricalLetterEntry {
  final String commentId;
  final String fanzineId;
  final String fanzineTitle;
  final String? volume;
  final String? issue;
  final String? fanzineShortCode;
  final String? coverImageUrl;
  final String? publishedDate;
  final String? imageId;
  final String? pageImageUrl;
  final int? pageNumber;
  final String letterText;
  final String? authorName;
  final String? authorHandle;
  final String? location;
  final double? distanceMiles;

  const HistoricalLetterEntry({
    required this.commentId,
    required this.fanzineId,
    required this.fanzineTitle,
    this.volume,
    this.issue,
    this.fanzineShortCode,
    this.coverImageUrl,
    this.publishedDate,
    this.imageId,
    this.pageImageUrl,
    this.pageNumber,
    required this.letterText,
    this.authorName,
    this.authorHandle,
    this.location,
    this.distanceMiles,
  });

  /// Creates a [HistoricalLetterEntry] from a raw comment document map.
  factory HistoricalLetterEntry.fromCommentMap(Map<String, dynamic> commentData, {double? distanceMiles}) {
    final contextMap = commentData['context'] as Map<String, dynamic>? ?? {};
    return HistoricalLetterEntry(
      commentId: (commentData['_id'] ?? commentData['id'] ?? '').toString(),
      fanzineId: (contextMap['fanzineId'] ?? '').toString(),
      fanzineTitle: (contextMap['fanzineTitle'] ?? 'Untitled Fanzine').toString(),
      volume: contextMap['volume']?.toString(),
      issue: contextMap['issue']?.toString(),
      fanzineShortCode: contextMap['shortCode']?.toString(),
      coverImageUrl: contextMap['coverImageUrl']?.toString(),
      publishedDate: commentData['historicalDate']?.toString(),
      imageId: commentData['contentId']?.toString(),
      pageImageUrl: commentData['pageImageUrl']?.toString(),
      pageNumber: commentData['pageNumber'] as int?,
      letterText: (commentData['text'] ?? '').toString(),
      authorName: commentData['displayName']?.toString(),
      authorHandle: commentData['username']?.toString(),
      location: commentData['location']?.toString(),
      distanceMiles: distanceMiles,
    );
  }

  /// Converts this letter entry into a clean structured Markdown block matching
  /// the 3-column publisher template layout seen in the historical magazines.
  String toPublisherMarkdown() {
    final buffer = StringBuffer();
    // 1. Cover Image
    if (coverImageUrl != null && coverImageUrl!.isNotEmpty) {
      buffer.writeln('{{IMAGE: $coverImageUrl}}');
      buffer.writeln();
    }
    // 2. Publication Title & Volume/Issue
    buffer.writeln(fanzineTitle);
    final volIssueParts = <String>[];
    if (volume != null && volume!.isNotEmpty) volIssueParts.add('Volume $volume');
    if (issue != null && issue!.isNotEmpty) volIssueParts.add('Issue $issue');
    if (volIssueParts.isNotEmpty) {
      buffer.writeln(volIssueParts.join(', '));
    }
    // 3. Published Date
    if (publishedDate != null && publishedDate!.isNotEmpty) {
      buffer.writeln(publishedDate);
    }
    buffer.writeln();
    // 4. Letter Scan Image
    if (pageImageUrl != null && pageImageUrl!.isNotEmpty) {
      buffer.writeln('{{IMAGE: $pageImageUrl}}');
      buffer.writeln();
    }
    // 5. Letter Content
    buffer.writeln(letterText);
    buffer.writeln();

    // 6. Author and Location sign-off (if not already embedded in transcription)
    final cleanTextLower = letterText.toLowerCase();
    final bool hasAuthor = authorName != null &&
        authorName!.isNotEmpty &&
        cleanTextLower.contains(authorName!.toLowerCase());
    final bool hasLocation = location != null &&
        location!.isNotEmpty &&
        cleanTextLower.contains(location!.toLowerCase());

    if (!hasAuthor && authorName != null && authorName!.isNotEmpty) {
      buffer.writeln(authorName);
    }
    if (!hasLocation && location != null && location!.isNotEmpty) {
      buffer.writeln(location);
    }
    buffer.writeln();
    return buffer.toString();
  }

  /// Resolves missing assets (cover image, publication date, volume, issue, scan page image)
  /// by querying Firestore documents asynchronously.
  static Future<HistoricalLetterEntry> resolveComplete({
    required Map<String, dynamic> rawComment,
    double? distanceMiles,
  }) async {
    final entry = HistoricalLetterEntry.fromCommentMap(rawComment, distanceMiles: distanceMiles);
    String resolvedTitle = entry.fanzineTitle;
    String? resolvedVolume = entry.volume;
    String? resolvedIssue = entry.issue;
    String? resolvedCover = entry.coverImageUrl;
    String? resolvedPubDate = entry.publishedDate;
    String? resolvedShortCode = entry.fanzineShortCode;
    String? resolvedPageUrl = entry.pageImageUrl;
    int? resolvedPageNum = entry.pageNumber;

    // 1. Resolve scan page image if needed
    if ((resolvedPageUrl == null || resolvedPageUrl.isEmpty) &&
        entry.imageId != null &&
        entry.imageId!.isNotEmpty) {
      try {
        final imgJson = await fsGetDoc('images/${entry.imageId}');
        final imgDoc = jsonDecode(imgJson);
        if (imgDoc['exists'] == true) {
          final data = imgDoc['data'] as Map<String, dynamic>? ?? {};
          resolvedPageUrl = data['fileUrl'] ?? data['listUrl'] ?? data['gridUrl'] ?? data['imageUrl'];
        }
      } catch (_) {}
    }

    // 2. Resolve parent fanzine metadata (cover, title, volume, issue, published date)
    if (entry.fanzineId.isNotEmpty) {
      if (UnsavedFanzineRegistry.fanzines.containsKey(entry.fanzineId)) {
        final fz = UnsavedFanzineRegistry.fanzines[entry.fanzineId]!;
        resolvedTitle = fz.title;
        resolvedVolume ??= fz.volume;
        resolvedIssue ??= fz.issue;
        resolvedShortCode = fz.shortCode;
        resolvedPubDate ??= fz.publishedDate;
        final pgs = UnsavedFanzineRegistry.pages[entry.fanzineId] ?? [];
        if (pgs.isNotEmpty) {
          resolvedCover ??= pgs.first.gridUrl ?? pgs.first.imageUrl;
        }
      } else {
        try {
          final fzJson = await fsGetDoc('fanzines/${entry.fanzineId}');
          final fzDoc = jsonDecode(fzJson);
          if (fzDoc['exists'] == true) {
            final fzData = fzDoc['data'] as Map<String, dynamic>? ?? {};
            resolvedTitle = fzData['title'] ?? resolvedTitle;
            resolvedVolume ??= fzData['volume']?.toString();
            resolvedIssue ??= fzData['issue']?.toString();
            resolvedShortCode ??= fzData['shortCode'];
            resolvedPubDate ??= fzData['publishedDate'];
            resolvedCover ??= fzData['gridCoverImage'];

            if (resolvedCover == null || resolvedCover.isEmpty) {
              final pagesJson = await fsQuery('fanzines/${entry.fanzineId}/pages', '', '', '', 'pageNumber');
              final List pList = jsonDecode(pagesJson) as List;
              if (pList.isNotEmpty) {
                final p0 = pList.first['data'] as Map<String, dynamic>? ?? {};
                resolvedCover = p0['gridUrl'] ?? p0['imageUrl'];
              }
            }
          }
        } catch (_) {}
      }
    }

    return HistoricalLetterEntry(
      commentId: entry.commentId,
      fanzineId: entry.fanzineId,
      fanzineTitle: resolvedTitle,
      volume: resolvedVolume,
      issue: resolvedIssue,
      fanzineShortCode: resolvedShortCode,
      coverImageUrl: resolvedCover,
      publishedDate: resolvedPubDate,
      imageId: entry.imageId,
      pageImageUrl: resolvedPageUrl,
      pageNumber: resolvedPageNum,
      letterText: entry.letterText,
      authorName: entry.authorName,
      authorHandle: entry.authorHandle,
      location: entry.location,
      distanceMiles: distanceMiles,
    );
  }
}

/// A Jaspr web component displaying a historical letter and its publication context
/// structured across 5 distinct stacked rows:
/// - Row 1: Cover image
/// - Row 2: Fanzine title
/// - Row 3: Date of publication
/// - Row 4: Page scan where the letter appeared
/// - Row 5: Text of the letter
class HistoricalLetterCard extends StatefulComponent {
  final HistoricalLetterEntry entry;
  final bool autoResolveMissing;
  final VoidCallback? onInsertIntoPage;

  const HistoricalLetterCard({
    required this.entry,
    this.autoResolveMissing = true,
    this.onInsertIntoPage,
    super.key,
  });

  @override
  State<HistoricalLetterCard> createState() => _HistoricalLetterCardState();
}

class _HistoricalLetterCardState extends State<HistoricalLetterCard> {
  late HistoricalLetterEntry _activeEntry;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _activeEntry = component.entry;
    if (component.autoResolveMissing &&
        (_activeEntry.coverImageUrl == null || _activeEntry.pageImageUrl == null)) {
      _resolveMetadata();
    }
  }

  @override
  void didUpdateComponent(HistoricalLetterCard oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.entry.commentId != component.entry.commentId) {
      _activeEntry = component.entry;
      if (component.autoResolveMissing &&
          (_activeEntry.coverImageUrl == null || _activeEntry.pageImageUrl == null)) {
        _resolveMetadata();
      }
    }
  }

  Future<void> _resolveMetadata() async {
    setState(() => _isResolving = true);
    try {
      final resolved = await HistoricalLetterEntry.resolveComplete(
        rawComment: {
          '_id': _activeEntry.commentId,
          'contentId': _activeEntry.imageId,
          'text': _activeEntry.letterText,
          'displayName': _activeEntry.authorName,
          'username': _activeEntry.authorHandle,
          'location': _activeEntry.location,
          'historicalDate': _activeEntry.publishedDate,
          'context': {
            'fanzineId': _activeEntry.fanzineId,
            'fanzineTitle': _activeEntry.fanzineTitle,
            'volume': _activeEntry.volume,
            'issue': _activeEntry.issue,
            'shortCode': _activeEntry.fanzineShortCode,
            'coverImageUrl': _activeEntry.coverImageUrl,
          }
        },
        distanceMiles: _activeEntry.distanceMiles,
      );
      if (mounted) {
        setState(() {
          _activeEntry = resolved;
          _isResolving = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Component _buildRow1CoverImage() {
    final cover = _activeEntry.coverImageUrl;
    final fzLink = _activeEntry.fanzineShortCode != null && _activeEntry.fanzineShortCode!.isNotEmpty
        ? '/${_activeEntry.fanzineShortCode}'
        : null;

    final imageWidget = div(
      attributes: const {
        'style':
        'width: 100%; max-width: 220px; aspect-ratio: 5 / 8; background-color: #F1B255; border-radius: 4px; overflow: hidden; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.1);'
      },
      [
        if (cover != null && cover.isNotEmpty)
          img(
            src: cover,
            attributes: const {
              'style': 'width: 100%; height: 100%; object-fit: contain; display: block;'
            },
          )
        else
          span(
            [Component.text('menu_book')],
            classes: 'material-symbols-outlined text-gray-400',
            attributes: const {'style': 'font-size: 48px; color: rgba(0,0,0,0.25);'},
          ),
      ],
    );

    return div(
      attributes: const {
        'style': 'width: 100%; display: flex; justify-content: center; padding: 8px 0;'
      },
      [
        if (fzLink != null)
          a(
            [imageWidget],
            href: fzLink,
            attributes: const {'style': 'text-decoration: none; cursor: pointer;'},
          )
        else
          imageWidget,
      ],
    );
  }

  Component _buildRow2FanzineTitle() {
    final title = _activeEntry.fanzineTitle;
    final fzLink = _activeEntry.fanzineShortCode != null && _activeEntry.fanzineShortCode!.isNotEmpty
        ? '/${_activeEntry.fanzineShortCode}'
        : null;

    final volIssueParts = <String>[];
    if (_activeEntry.volume != null && _activeEntry.volume!.isNotEmpty) {
      volIssueParts.add('Vol. ${_activeEntry.volume}');
    }
    if (_activeEntry.issue != null && _activeEntry.issue!.isNotEmpty) {
      volIssueParts.add('No. ${_activeEntry.issue}');
    }

    return div(
      attributes: const {
        'style':
        'width: 100%; text-align: center; padding: 6px 0; border-top: 1px solid #f0f0f0;'
      },
      [
        span(
          [Component.text('PUBLICATION')],
          attributes: const {
            'style':
            'font-size: 9px; font-weight: bold; color: #888; letter-spacing: 0.8px; text-transform: uppercase; display: block; margin-bottom: 2px;'
          },
        ),
        if (fzLink != null)
          a(
            [Component.text(title)],
            href: fzLink,
            classes: 'hover:underline',
            attributes: const {
              'style':
              'font-size: 16px; font-weight: 900; color: #111; text-decoration: none; font-family: inherit;'
            },
          )
        else
          h3(
            [Component.text(title)],
            attributes: const {
              'style': 'font-size: 16px; font-weight: 900; color: #111; margin: 0;'
            },
          ),
        if (volIssueParts.isNotEmpty)
          span(
            [Component.text(volIssueParts.join(', '))],
            attributes: const {
              'style': 'font-size: 11px; color: #666; font-weight: 500; display: block; margin-top: 2px;'
            },
          ),
      ],
    );
  }

  Component _buildRow3DateOfPublication() {
    final date = _activeEntry.publishedDate;
    final location = _activeEntry.location;
    final dist = _activeEntry.distanceMiles;

    return div(
      attributes: const {
        'style':
        'width: 100%; text-align: center; padding: 4px 0 8px 0; display: flex; justify-content: center; align-items: center; gap: 8px; flex-wrap: wrap;'
      },
      [
        if (date != null && date.isNotEmpty)
          span(
            [
              span([Component.text('calendar_today')],
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px; margin-right: 4px; vertical-align: middle;'}),
              Component.text(date)
            ],
            attributes: const {
              'style':
              'font-size: 11px; font-weight: bold; color: #555; background: #f3f4f6; padding: 3px 8px; border-radius: 12px;'
            },
          ),
        if (location != null && location.isNotEmpty)
          span(
            [
              span([Component.text('pin_drop')],
                  classes: 'material-symbols-outlined',
                  attributes: const {'style': 'font-size: 13px; margin-right: 3px; vertical-align: middle;'}),
              Component.text(dist != null ? '$location (${dist.toStringAsFixed(1)} mi)' : location)
            ],
            attributes: const {
              'style':
              'font-size: 11px; font-weight: 600; color: #16a34a; background: #ecfdf5; padding: 3px 8px; border-radius: 12px; border: 1px solid #bbf7d0;'
            },
          ),
      ],
    );
  }

  Component _buildRow4PageScanImage() {
    final pageImg = _activeEntry.pageImageUrl;

    return div(
      attributes: const {
        'style':
        'width: 100%; display: flex; flex-direction: column; align-items: center; padding: 10px 0; border-top: 1px solid #f0f0f0;'
      },
      [
        span(
          [Component.text('LETTER COLUMN PAGE SCAN')],
          attributes: const {
            'style':
            'font-size: 9px; font-weight: bold; color: #888; letter-spacing: 0.8px; text-transform: uppercase; margin-bottom: 6px;'
          },
        ),
        if (pageImg != null && pageImg.isNotEmpty)
          div(
            attributes: const {
              'style':
              'width: 100%; max-width: 480px; aspect-ratio: 5 / 8; background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 6px; overflow: hidden; display: flex; align-items: center; justify-content: center; box-shadow: 0 1px 4px rgba(0,0,0,0.06);'
            },
            [
              img(
                src: pageImg,
                attributes: const {
                  'style': 'width: 100%; height: 100%; object-fit: contain; display: block;'
                },
              )
            ],
          )
        else
          div(
            attributes: const {
              'style':
              'width: 100%; max-width: 320px; padding: 24px; background: #f8fafc; border: 1px dashed #cbd5e1; border-radius: 6px; text-align: center;'
            },
            [
              span([Component.text('image_not_supported')],
                  classes: 'material-symbols-outlined text-gray-300',
                  attributes: const {'style': 'font-size: 32px;'}),
              p([Component.text('Page scan loading or unassigned.')],
                  attributes: const {'style': 'font-size: 11px; color: #888; font-style: italic; margin: 4px 0 0 0;'}),
            ],
          ),
      ],
    );
  }

  Component _buildRow5LetterText() {
    final writer = _activeEntry.authorName ?? 'Anonymous Correspondent';
    final handle = _activeEntry.authorHandle;
    final text = _activeEntry.letterText;

    return div(
      attributes: const {
        'style':
        'width: 100%; padding: 16px 0 8px 0; border-top: 1px solid #f0f0f0; display: flex; flex-direction: column; gap: 8px;'
      },
      [
        div(
          attributes: const {
            'style': 'display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 6px;'
          },
          [
            div(
              attributes: const {'style': 'display: flex; align-items: center; gap: 6px;'},
              [
                span([Component.text(writer)],
                    attributes: const {'style': 'font-size: 13px; font-weight: bold; color: #111;'}),
                if (handle != null && handle.isNotEmpty)
                  a(
                    [Component.text('@$handle')],
                    href: '/@$handle',
                    classes: 'hover:underline',
                    attributes: const {
                      'style': 'font-size: 11px; font-weight: bold; color: #6750A4; text-decoration: none;'
                    },
                  ),
              ],
            ),
            if (component.onInsertIntoPage != null)
              button(
                [
                  span([Component.text('add_circle')],
                      classes: 'material-symbols-outlined',
                      attributes: const {'style': 'font-size: 14px; margin-right: 4px;'}),
                  Component.text('insert into page')
                ],
                classes: 'profile-btn',
                attributes: const {
                  'type': 'button',
                  'style':
                  'padding: 4px 10px; font-size: 10px; font-weight: bold; border: 1px solid #6750A4; color: #6750A4; background: white; cursor: pointer; border-radius: 14px; display: inline-flex; align-items: center;'
                },
                events: {'click': (e) => component.onInsertIntoPage!()},
              ),
          ],
        ),
        div(
          attributes: const {
            'style':
            'background: #fffdfa; border-left: 3px solid #F1B255; padding: 12px 14px; border-radius: 0 4px 4px 0;'
          },
          [
            p(
              [Component.text(text)],
              attributes: const {
                'style':
                'font-family: Georgia, serif; font-size: 13.5px; line-height: 1.6; color: #222; text-align: justify; margin: 0; white-space: pre-wrap; word-break: break-word;'
              },
            )
          ],
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'historical-letter-card bg-white rounded-lg shadow-sm border border-gray-200',
      attributes: const {
        'style':
        'display: flex; flex-direction: column; width: 100%; max-width: 600px; padding: 16px; background: white; border: 1px solid #e2e8f0; border-radius: 8px; box-sizing: border-box; margin: 0 auto 20px auto;'
      },
      [
        if (_isResolving)
          div(
            [Component.text('resolving archival metadata...')],
            attributes: const {
              'style':
              'font-size: 10px; font-style: italic; color: #6750A4; text-align: right; margin-bottom: 4px;'
            },
          ),
        _buildRow1CoverImage(),
        _buildRow2FanzineTitle(),
        _buildRow3DateOfPublication(),
        _buildRow4PageScanImage(),
        _buildRow5LetterText(),
      ],
    );
  }
}