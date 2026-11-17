/// Companion half-page rendering modes for printable 2-page spread JPEGs.
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

/// Request payload describing both halves of a printable 11" x 8.5" (3300x2550) spread.
class PrintableSpreadRequest {
  final String fileName;
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

/// Server VM stub for generating and downloading a printable 300-DPI 2-page spread JPEG.
Future<bool> generateAndDownloadSpreadJpg(PrintableSpreadRequest request) async {
  return false;
}
