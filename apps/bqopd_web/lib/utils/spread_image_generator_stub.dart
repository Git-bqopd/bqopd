/// Output file formats supported for printable 2-page spread downloads.
enum SpreadDownloadFormat {
  jpg,
  pdf,
}

/// Companion half-page rendering modes for printable 2-page spread downloads.
enum SpreadCompanionKind {
  fanzinePage,
  duplicatePage,
  houseAd,
  wallCalendar,
  pageComments,
  businessHours,
}

/// Single day row for a printable Business Hours front-door sign.
class BusinessHoursRowData {
  final String dayLabel;
  final bool isOpen;
  final String open;
  final String close;

  const BusinessHoursRowData({
    required this.dayLabel,
    required this.isOpen,
    this.open = '',
    this.close = '',
  });
}

/// Complete payload for rendering a Business Hours of Operation sign half-page.
class BusinessHoursSignData {
  final String displayName;
  final String username;
  final List<String> addressLines;
  final List<BusinessHoursRowData> rows;

  const BusinessHoursSignData({
    required this.displayName,
    required this.username,
    this.addressLines = const [],
    required this.rows,
  });
}

/// Request payload describing both halves of a printable US Letter Landscape
/// 2-page spread (`11" x 8.5"` / `3300x2550 px` at 300 DPI, `792 x 612 pt`).
class PrintableSpreadRequest {
  final String fileName;
  final SpreadDownloadFormat format;
  final String fanzineTitle;
  final String canonicalUrl;
  final String shortCode;
  final String? masterIndicia;
  final int pageNumber;
  final bool currentPageOnLeft;

  // Primary page (the page the user is viewing)
  final String? primaryImageUrl;
  final String? primaryFallbackText;
  final String? primaryTemplateId;

  // Companion page (the selected other side of the spread)
  final SpreadCompanionKind companionKind;
  final String? companionImageUrl;
  final String? companionFallbackText;
  final int? companionPageNumber;
  final String? adHeadline;
  final String? adBody;
  final int calendarStartMonth;
  final int calendarStartYear;
  final List<Map<String, dynamic>> comments;
  final BusinessHoursSignData? businessSign;

  const PrintableSpreadRequest({
    required this.fileName,
    this.format = SpreadDownloadFormat.jpg,
    required this.fanzineTitle,
    required this.canonicalUrl,
    required this.shortCode,
    this.masterIndicia,
    required this.pageNumber,
    required this.currentPageOnLeft,
    this.primaryImageUrl,
    this.primaryFallbackText,
    this.primaryTemplateId,
    required this.companionKind,
    this.companionImageUrl,
    this.companionFallbackText,
    this.companionPageNumber,
    this.adHeadline,
    this.adBody,
    required this.calendarStartMonth,
    required this.calendarStartYear,
    this.comments = const [],
    this.businessSign,
  });
}

/// Descriptor for a single page inside a full-issue saddle-stitch PDF export.
class FullIssueSpreadPage {
  final int pageNumber;
  final String? imageUrl;
  final String? fallbackText;
  final String? templateId;

  const FullIssueSpreadPage({
    required this.pageNumber,
    this.imageUrl,
    this.fallbackText,
    this.templateId,
  });
}

/// Request payload for exporting an entire fanzine issue as a saddle-stitch
/// imposed multi-page US Letter Landscape `11" x 8.5"` (`792 x 612 pt`) PDF.
class FullIssuePdfRequest {
  final String fileName;
  final String fanzineTitle;
  final String canonicalUrl;
  final String shortCode;
  final String? masterIndicia;
  final List<FullIssueSpreadPage> pages;
  final int calendarStartMonth;
  final int calendarStartYear;

  const FullIssuePdfRequest({
    required this.fileName,
    required this.fanzineTitle,
    required this.canonicalUrl,
    required this.shortCode,
    this.masterIndicia,
    required this.pages,
    required this.calendarStartMonth,
    required this.calendarStartYear,
  });
}

/// Computes the 1-indexed `(leftPage, rightPage)` saddle-stitch imposition pairs
/// for an issue with [totalPages] pages.
///
/// For a 24-page issue, produces:
/// `[24|01], [02|23], [22|03], [04|21], [20|05], [06|19],`
/// `[18|07], [08|17], [16|09], [10|15], [14|11], [12|13]`.
///
/// If [totalPages] is not a multiple of 4, pads up to the next multiple of 4
/// and represents trailing blank padding slots as `null`.
List<(int?, int?)> buildSaddleStitchImpositionPairs(int totalPages) {
  if (totalPages <= 0) return const [];
  final int paddedTotal = ((totalPages + 3) ~/ 4) * 4;
  final int sheetCount = paddedTotal ~/ 2;
  final List<(int?, int?)> pairs = [];

  for (int s = 0; s < sheetCount; s++) {
    final int rawLeft = s.isEven ? (paddedTotal - s) : (s + 1);
    final int rawRight = s.isEven ? (s + 1) : (paddedTotal - s);
    final int? leftPage = rawLeft <= totalPages ? rawLeft : null;
    final int? rightPage = rawRight <= totalPages ? rawRight : null;
    pairs.add((leftPage, rightPage));
  }

  return pairs;
}

/// Server VM stub for generating and downloading a printable 300-DPI 2-page spread.
Future<bool> generateAndDownloadSpread(PrintableSpreadRequest request) async {
  return false;
}

/// Backwards-compatible alias for [generateAndDownloadSpread].
Future<bool> generateAndDownloadSpreadJpg(PrintableSpreadRequest request) {
  return generateAndDownloadSpread(request);
}

/// Server VM stub for generating and downloading a full-issue saddle-stitch PDF.
Future<bool> generateAndDownloadFullIssuePdf(
    FullIssuePdfRequest request, {
      void Function(int currentSheet, int totalSheets)? onProgress,
    }) async {
  return false;
}