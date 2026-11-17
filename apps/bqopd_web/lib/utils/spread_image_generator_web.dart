import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'spread_image_generator_stub.dart';
export 'spread_image_generator_stub.dart'
    show
        SpreadCompanionKind,
        BusinessHoursRowData,
        BusinessHoursSignData,
        PrintableSpreadRequest;

const List<String> _monthNames = [
  'JANUARY',
  'FEBRUARY',
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUGUST',
  'SEPTEMBER',
  'OCTOBER',
  'NOVEMBER',
  'DECEMBER',
];

const List<String> _shortMonthNames = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Generates a 300-DPI US Letter Landscape (3300 x 2550 px) two-page spread JPEG
/// and triggers an immediate file download in the browser.
Future<bool> generateAndDownloadSpreadJpg(PrintableSpreadRequest request) async {
  try {
    // 11.0" x 8.5" at 300 DPI = 3300 x 2550 px
    const int sheetWidth = 3300;
    const int sheetHeight = 2550;

    // Each half-sheet is 1650 x 2550.
    // A 1500 x 2400 content box leaves a symmetric 75px (0.25") safe print margin
    // on all sides and matches the exact 5:8 (2000 x 3200 @ 0.75x) page ratio.
    const double leftPageX = 75.0;
    const double rightPageX = 1725.0;
    const double pageY = 75.0;
    const double pageScale = 0.75; // 2000 * 0.75 = 1500, 3200 * 0.75 = 2400

    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = sheetWidth;
    canvas.height = sheetHeight;

    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return false;

    // 1. Crisp white paper sheet background
    ctx.fillStyle = '#FFFFFF'.toJS;
    ctx.fillRect(0, 0, sheetWidth, sheetHeight);

    // 2. Subtle center fold / cut guide in the 150px center gutter (x = 1650)
    _drawCenterFoldGuides(ctx, sheetWidth, sheetHeight);

    // 3. Preload primary & companion images in parallel (CORS-safe)
    final primaryImgFuture = _loadCorsSafeImage(request.primaryImageUrl);
    final Future<web.HTMLImageElement?> companionImgFuture =
        (request.companionKind == SpreadCompanionKind.fanzinePage &&
                request.companionImageUrl != null &&
                request.companionImageUrl!.isNotEmpty)
            ? _loadCorsSafeImage(request.companionImageUrl)
            : Future.value(null);

    final results = await Future.wait([primaryImgFuture, companionImgFuture]);
    final primaryImg = results[0];
    final companionImg = results[1];

    final double primaryX = request.currentPageOnLeft ? leftPageX : rightPageX;
    final double companionX =
        request.currentPageOnLeft ? rightPageX : leftPageX;

    // 4. Draw Primary Page (the page the user is viewing)
    ctx.save();
    ctx.translate(primaryX, pageY);
    ctx.scale(pageScale, pageScale);
    if (primaryImg != null) {
      _drawContainedPageImage(ctx, primaryImg);
    } else if (request.primaryTemplateId == 'calendar_left' ||
        request.primaryTemplateId == 'calendar_right') {
      _drawWallCalendarPage(
        ctx,
        startMonth: request.calendarStartMonth,
        startYear: request.calendarStartYear,
        fanzineTitle: request.fanzineTitle,
        pageNumber: request.pageNumber,
        canonicalUrl: request.canonicalUrl,
      );
    } else {
      _drawFallbackTextPage(
        ctx,
        title: '${request.fanzineTitle} · Page ${request.pageNumber}',
        body: request.primaryFallbackText ?? '',
        canonicalUrl: request.canonicalUrl,
      );
    }
    ctx.restore();

    // 5. Draw Companion Page (the user's selected other half of the spread)
    ctx.save();
    ctx.translate(companionX, pageY);
    ctx.scale(pageScale, pageScale);

    switch (request.companionKind) {
      case SpreadCompanionKind.duplicatePage:
        if (primaryImg != null) {
          _drawContainedPageImage(ctx, primaryImg);
        } else {
          _drawFallbackTextPage(
            ctx,
            title: '${request.fanzineTitle} · Page ${request.pageNumber}',
            body: request.primaryFallbackText ?? '',
            canonicalUrl: request.canonicalUrl,
          );
        }
        break;

      case SpreadCompanionKind.fanzinePage:
        if (companionImg != null) {
          _drawContainedPageImage(ctx, companionImg);
        } else if (request.companionFallbackText != null &&
            request.companionFallbackText!.trim().isNotEmpty) {
          _drawFallbackTextPage(
            ctx,
            title:
                '${request.fanzineTitle} · Page ${request.companionPageNumber ?? ""}',
            body: request.companionFallbackText!,
            canonicalUrl: request.canonicalUrl,
          );
        } else {
          _drawHouseAdPage(
            ctx,
            fanzineTitle: request.fanzineTitle,
            headline: request.adHeadline,
            body: request.adBody,
            indicia: request.masterIndicia,
            canonicalUrl: request.canonicalUrl,
            shortCode: request.shortCode,
          );
        }
        break;

      case SpreadCompanionKind.houseAd:
        _drawHouseAdPage(
          ctx,
          fanzineTitle: request.fanzineTitle,
          headline: request.adHeadline,
          body: request.adBody,
          indicia: request.masterIndicia,
          canonicalUrl: request.canonicalUrl,
          shortCode: request.shortCode,
        );
        break;

      case SpreadCompanionKind.wallCalendar:
        _drawWallCalendarPage(
          ctx,
          startMonth: request.calendarStartMonth,
          startYear: request.calendarStartYear,
          fanzineTitle: request.fanzineTitle,
          pageNumber: request.pageNumber,
          canonicalUrl: request.canonicalUrl,
        );
        break;

      case SpreadCompanionKind.pageComments:
        _drawCommentsPage(
          ctx,
          fanzineTitle: request.fanzineTitle,
          pageNumber: request.pageNumber,
          comments: request.comments,
          canonicalUrl: request.canonicalUrl,
        );
        break;

      case SpreadCompanionKind.businessHours:
        _drawBusinessHoursPage(
          ctx,
          sign: request.businessSign,
          canonicalUrl: request.canonicalUrl,
        );
        break;
    }

    ctx.restore();

    // 6. Encode as high-quality print JPEG and download via Blob URL
    final String dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
    final int commaIdx = dataUrl.indexOf(',');
    if (commaIdx == -1) return false;

    final Uint8List jpegBytes = base64Decode(dataUrl.substring(commaIdx + 1));
    final blob = web.Blob(
      [jpegBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    final String blobUrl = web.URL.createObjectURL(blob);

    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = blobUrl;
    anchor.download = request.fileName;
    anchor.style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();

    web.window.setTimeout(
      (() {
        web.URL.revokeObjectURL(blobUrl);
      }).toJS,
      5000.toJS,
    );

    return true;
  } catch (e) {
    print('[generateAndDownloadSpreadJpg Error] $e');
    return false;
  }
}

void _drawCenterFoldGuides(
  web.CanvasRenderingContext2D ctx,
  int sheetWidth,
  int sheetHeight,
) {
  final double centerX = sheetWidth / 2.0;
  ctx.save();

  // Faint dashed fold line down the center
  ctx.strokeStyle = '#E2E8F0'.toJS;
  ctx.lineWidth = 2.0;
  ctx.setLineDash([14.0.toJS, 14.0.toJS].toJS);
  ctx.beginPath();
  ctx.moveTo(centerX, 64);
  ctx.lineTo(centerX, sheetHeight - 64);
  ctx.stroke();

  // Crisp printer trim / fold ticks in top and bottom outer margins
  ctx.setLineDash(<JSNumber>[].toJS);
  ctx.strokeStyle = '#94A3B8'.toJS;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(centerX, 18);
  ctx.lineTo(centerX, 50);
  ctx.moveTo(centerX, sheetHeight - 50);
  ctx.lineTo(centerX, sheetHeight - 18);
  ctx.stroke();

  ctx.restore();
}

/// Loads an image safely for `<canvas>` pixel extraction without triggering
/// tainted-canvas errors when the same URL was previously cached by `<img>`.
Future<web.HTMLImageElement?> _loadCorsSafeImage(String? rawUrl) async {
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;
  final String url = rawUrl.trim();

  // Data URIs, Blob URLs, and relative local assets can be loaded directly
  if (url.startsWith('data:') ||
      url.startsWith('blob:') ||
      (!url.startsWith('http://') && !url.startsWith('https://'))) {
    return _loadHtmlImage(url, useCors: false);
  }

  // Primary strategy for remote URLs: fetch with mode='cors' & cache='reload'
  // so Chrome/Safari never return an un-CORS-headered memory-cache entry.
  try {
    final response = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(mode: 'cors', cache: 'reload'),
        )
        .toDart;
    if (response.ok) {
      final blob = await response.blob().toDart;
      final objectUrl = web.URL.createObjectURL(blob);
      final img = await _loadHtmlImage(objectUrl, useCors: false);
      web.URL.revokeObjectURL(objectUrl);
      if (img != null) return img;
    }
  } catch (_) {}

  // Fallback: direct HTMLImageElement with crossOrigin = 'anonymous' + cache-buster
  final String sep = url.contains('?') ? '&' : '?';
  final String bustedUrl =
      '$url${sep}_bqopd_cors=${DateTime.now().millisecondsSinceEpoch}';
  return _loadHtmlImage(bustedUrl, useCors: true);
}

Future<web.HTMLImageElement?> _loadHtmlImage(
  String src, {
  required bool useCors,
}) {
  final completer = Completer<web.HTMLImageElement?>();
  final img = web.document.createElement('img') as web.HTMLImageElement;
  Timer? timeoutTimer;
  bool done = false;

  void finish(web.HTMLImageElement? res) {
    if (done) return;
    done = true;
    timeoutTimer?.cancel();
    completer.complete(res);
  }

  timeoutTimer = Timer(const Duration(seconds: 7), () => finish(null));
  if (useCors) {
    img.crossOrigin = 'anonymous';
  }
  img.onload = (web.Event _) {
    finish(img.naturalWidth > 0 ? img : null);
  }.toJS;
  img.onerror = (web.Event _) {
    finish(null);
  }.toJS;
  img.src = src;
  return completer.future;
}

/// Draws a loaded page image inside the 2000 x 3200 half-page canvas box
/// preserving aspect ratio (`object-fit: contain`).
void _drawContainedPageImage(
  web.CanvasRenderingContext2D ctx,
  web.HTMLImageElement img,
) {
  const double boxW = 2000.0;
  const double boxH = 3200.0;

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.fillRect(0, 0, boxW, boxH);

  final double imgW = img.naturalWidth.toDouble();
  final double imgH = img.naturalHeight.toDouble();
  if (imgW <= 0 || imgH <= 0) return;

  final double scale = math.min(boxW / imgW, boxH / imgH);
  final double drawW = imgW * scale;
  final double drawH = imgH * scale;
  final double offsetX = (boxW - drawW) / 2.0;
  final double offsetY = (boxH - drawH) / 2.0;

  ctx.drawImage(img, offsetX, offsetY, drawW, drawH);

  // Subtle hairline frame so white-edged pages still show clean boundaries
  ctx.strokeStyle = '#E2E8F0'.toJS;
  ctx.lineWidth = 3.0;
  ctx.strokeRect(1.5, 1.5, boxW - 3.0, boxH - 3.0);
}

/// Renders a 6-month Pin-Up Wall Calendar in native 2000 x 3200 space.
void _drawWallCalendarPage(
  web.CanvasRenderingContext2D ctx, {
  required int startMonth,
  required int startYear,
  required String fanzineTitle,
  required int pageNumber,
  required String canonicalUrl,
}) {
  const double w = 2000.0;
  const double h = 3200.0;

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.fillRect(0, 0, w, h);

  // Outer bold zine frame (12px)
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 12.0;
  ctx.strokeRect(6, 6, w - 12, h - 12);

  // Compute 6-month span label
  final DateTime firstDate = DateTime(startYear, startMonth, 1);
  final DateTime lastDate = DateTime(startYear, startMonth + 5, 1);
  final String spanLabel =
      '${_shortMonthNames[firstDate.month - 1]} ${firstDate.year} – ${_shortMonthNames[lastDate.month - 1]} ${lastDate.year}';

  // Top Masthead Banner (y = 12..230)
  ctx.fillStyle = '#111111'.toJS;
  ctx.fillRect(12, 12, w - 24, 218);

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.font = '900 76px "Impact", "Anton", "Arial Black", sans-serif';
  ctx.textBaseline = 'alphabetic';
  ctx.fillText('WALL CALENDAR', 64, 118);

  ctx.font = 'bold 34px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillStyle = '#F1B255'.toJS;
  ctx.fillText(spanLabel, 66, 178);

  // Right-aligned zine badge inside masthead
  final String cleanTitle = fanzineTitle.trim().isEmpty
      ? 'BQOPD FANZINE'
      : fanzineTitle.trim().toUpperCase();
  final String truncTitle =
      cleanTitle.length > 30 ? '${cleanTitle.substring(0, 28)}…' : cleanTitle;
  ctx.textAlign = 'right';
  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.font = 'bold 30px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(truncTitle, w - 64, 112);
  ctx.fillStyle = '#CBD5E1'.toJS;
  ctx.font = '26px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('PIN-UP SPREAD · PAGE $pageNumber', w - 64, 162);
  ctx.textAlign = 'left';

  // 6-Month Grid Area: 2 columns x 3 rows (y = 230..2570, height = 2340)
  const double gridTop = 230.0;
  const double gridHeight = 2340.0;
  const double cellW = (w - 24.0) / 2.0; // 988 px
  const double cellH = gridHeight / 3.0; // 780 px

  final DateTime now = DateTime.now();

  for (int idx = 0; idx < 6; idx++) {
    final int col = idx % 2;
    final int row = idx ~/ 2;
    final double cellX = 12.0 + col * cellW;
    final double cellY = gridTop + row * cellH;

    final DateTime mDate = DateTime(startYear, startMonth + idx, 1);
    _drawSingleCalendarMonthCell(
      ctx,
      x: cellX,
      y: cellY,
      width: cellW,
      height: cellH,
      year: mDate.year,
      month: mDate.month,
      today: now,
    );

    // Cell dividers
    ctx.strokeStyle = '#000000'.toJS;
    ctx.lineWidth = 8.0;
    if (col == 0) {
      ctx.beginPath();
      ctx.moveTo(cellX + cellW, cellY);
      ctx.lineTo(cellX + cellW, cellY + cellH);
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(cellX, cellY + cellH);
    ctx.lineTo(cellX + cellW, cellY + cellH);
    ctx.stroke();
  }

  // Bottom Pin-Up Notes Section (y = 2570..3116)
  const double notesTop = 2570.0;
  ctx.fillStyle = '#000000'.toJS;
  ctx.font = '900 34px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('NOTES · SHOWS · DEADLINES', 64, notesTop + 66);

  ctx.strokeStyle = '#94A3B8'.toJS;
  ctx.lineWidth = 2.5;
  for (int line = 0; line < 4; line++) {
    final double ly = notesTop + 160.0 + line * 102.0;
    ctx.beginPath();
    ctx.moveTo(64, ly);
    ctx.lineTo(w - 64, ly);
    ctx.stroke();
  }

  // Footer Colophon Bar (y = 3116..3188)
  ctx.fillStyle = '#F1F5F9'.toJS;
  ctx.fillRect(12, 3116, w - 24, 72);
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 6.0;
  ctx.beginPath();
  ctx.moveTo(12, 3116);
  ctx.lineTo(w - 12, 3116);
  ctx.stroke();

  ctx.fillStyle = '#1E293B'.toJS;
  ctx.font = 'bold 26px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(canonicalUrl.replaceFirst('https://', ''), 64, 3162);

  ctx.textAlign = 'right';
  ctx.fillStyle = '#475569'.toJS;
  ctx.font = 'bold 24px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('BQOPD PRINTABLE SPREAD', w - 64, 3162);
  ctx.textAlign = 'left';
}

void _drawSingleCalendarMonthCell(
  web.CanvasRenderingContext2D ctx, {
  required double x,
  required double y,
  required double width,
  required double height,
  required int year,
  required int month,
  required DateTime today,
}) {
  const double pad = 22.0;
  final double innerX = x + pad;
  final double innerW = width - pad * 2;

  // Month title bar
  ctx.fillStyle = '#000000'.toJS;
  ctx.font = '900 40px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('${_monthNames[month - 1]} $year', innerX + 6, y + 58);

  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 5.0;
  ctx.beginPath();
  ctx.moveTo(innerX, y + 76);
  ctx.lineTo(innerX + innerW, y + 76);
  ctx.stroke();

  // Weekday headers (SUN..SAT)
  const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  final double colW = innerW / 7.0;
  ctx.font = 'bold 22px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillStyle = '#334155'.toJS;
  ctx.textAlign = 'center';
  for (int d = 0; d < 7; d++) {
    ctx.fillText(weekdays[d], innerX + colW * d + colW / 2.0, y + 112);
  }
  ctx.textAlign = 'left';

  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 3.0;
  ctx.beginPath();
  ctx.moveTo(innerX, y + 126);
  ctx.lineTo(innerX + innerW, y + 126);
  ctx.stroke();

  // Day cells (6 rows so every month aligns cleanly)
  final int daysInMonth = DateTime(year, month + 1, 0).day;
  // Dart weekday: Mon=1 .. Sun=7 -> Sunday-first index: Sun=0, Mon=1..Sat=6
  final int firstWeekdayOffset = DateTime(year, month, 1).weekday % 7;
  final double gridStartY = y + 126.0;
  final double gridAvailH = height - 146.0;
  final double rowH = gridAvailH / 6.0;

  // Subtle internal day grid lines
  ctx.strokeStyle = '#CBD5E1'.toJS;
  ctx.lineWidth = 2.0;
  for (int r = 1; r <= 6; r++) {
    final double ry = gridStartY + r * rowH;
    ctx.beginPath();
    ctx.moveTo(innerX, ry);
    ctx.lineTo(innerX + innerW, ry);
    ctx.stroke();
  }
  for (int c = 0; c <= 7; c++) {
    final double cx = innerX + c * colW;
    ctx.beginPath();
    ctx.moveTo(cx, gridStartY);
    ctx.lineTo(cx, gridStartY + gridAvailH);
    ctx.stroke();
  }

  // Day numbers
  for (int day = 1; day <= daysInMonth; day++) {
    final int slot = firstWeekdayOffset + (day - 1);
    final int r = slot ~/ 7;
    final int c = slot % 7;
    final double cellLeft = innerX + c * colW;
    final double cellTop = gridStartY + r * rowH;

    final bool isToday =
        (year == today.year && month == today.month && day == today.day);
    if (isToday) {
      ctx.fillStyle = '#000000'.toJS;
      ctx.fillRect(cellLeft + 4, cellTop + 4, colW - 8, 42);
      ctx.fillStyle = '#FFFFFF'.toJS;
      ctx.font = '900 26px "Arimo", "Segoe UI", Arial, sans-serif';
      ctx.fillText('$day', cellLeft + 14, cellTop + 34);
    } else {
      ctx.fillStyle = (c == 0 || c == 6) ? '#475569'.toJS : '#0F172A'.toJS;
      ctx.font = 'bold 26px "Arimo", "Segoe UI", Arial, sans-serif';
      ctx.fillText('$day', cellLeft + 12, cellTop + 34);
    }
  }
}

/// Renders a 2-column Comments & Letters companion page in 2000 x 3200 space.
void _drawCommentsPage(
  web.CanvasRenderingContext2D ctx, {
  required String fanzineTitle,
  required int pageNumber,
  required List<Map<String, dynamic>> comments,
  required String canonicalUrl,
}) {
  const double w = 2000.0;
  const double h = 3200.0;

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.fillRect(0, 0, w, h);

  // Outer zine border
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 12.0;
  ctx.strokeRect(6, 6, w - 12, h - 12);

  // Masthead
  ctx.fillStyle = '#111111'.toJS;
  ctx.fillRect(12, 12, w - 24, 210);

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.font = '900 72px "Impact", "Anton", "Arial Black", sans-serif';
  ctx.fillText('COMMENTS & LETTERS', 64, 114);

  final String cleanTitle = fanzineTitle.trim().isEmpty
      ? 'FANZINE'
      : fanzineTitle.trim().toUpperCase();
  final String sub =
      '$cleanTitle · PAGE $pageNumber  (${comments.length} ${comments.length == 1 ? "RESPONSE" : "RESPONSES"})';
  ctx.fillStyle = '#F1B255'.toJS;
  ctx.font = 'bold 30px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(
    sub.length > 68 ? '${sub.substring(0, 66)}…' : sub,
    66,
    174,
  );

  // 2-column layout body (y = 260..3060)
  const double colTop = 270.0;
  const double colBottom = 3050.0;
  const double colWidth = 880.0;
  final List<double> colX = [64.0, 1056.0];

  // Center vertical column divider
  ctx.fillStyle = '#000000'.toJS;
  ctx.fillRect(996, 260, 8, 2800);

  int colIdx = 0;
  double cursorY = colTop;

  if (comments.isNotEmpty) {
    for (int i = 0; i < comments.length; i++) {
      final c = comments[i];
      final String author = _resolveCommentAuthor(c);
      final String meta = _resolveCommentMeta(c);
      final String rawText = (c['text'] ?? '').toString().trim();
      if (rawText.isEmpty) continue;

      final List<String> lines = _wrapCanvasText(
        ctx,
        rawText,
        maxWidth: colWidth,
        font: '30px Georgia, "Times New Roman", serif',
      );

      final double blockHeight =
          50.0 + (meta.isNotEmpty ? 34.0 : 0.0) + lines.length * 42.0 + 44.0;

      if (cursorY + blockHeight > colBottom) {
        if (colIdx == 0) {
          colIdx = 1;
          cursorY = colTop;
        } else {
          // Indicate additional comments online when both columns fill up
          ctx.fillStyle = '#475569'.toJS;
          ctx.font = 'italic 28px Georgia, serif';
          ctx.fillText(
            '+ ${comments.length - i} more responses at ${canonicalUrl.replaceFirst("https://", "")}',
            colX[1],
            colBottom + 20,
          );
          break;
        }
      }

      final double x = colX[colIdx];

      // Author line
      ctx.fillStyle = '#0F172A'.toJS;
      ctx.font = '900 31px "Arimo", "Segoe UI", Arial, sans-serif';
      ctx.fillText(author, x, cursorY + 30);
      cursorY += 42;

      if (meta.isNotEmpty) {
        ctx.fillStyle = '#64748B'.toJS;
        ctx.font = 'bold 23px "Arimo", "Segoe UI", Arial, sans-serif';
        ctx.fillText(meta.toUpperCase(), x, cursorY + 22);
        cursorY += 34;
      }

      // Comment text lines
      ctx.fillStyle = '#1E293B'.toJS;
      ctx.font = '30px Georgia, "Times New Roman", serif';
      for (final line in lines) {
        if (cursorY + 38 > colBottom) break;
        ctx.fillText(line, x, cursorY + 30);
        cursorY += 42;
      }

      // Divider rule
      cursorY += 18;
      ctx.strokeStyle = '#CBD5E1'.toJS;
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.moveTo(x, cursorY);
      ctx.lineTo(x + colWidth, cursorY);
      ctx.stroke();
      cursorY += 28;
    }
  }

  // If space remains in the active column (or when there are 0 comments),
  // draw handwritten marginalia / note lines so readers can jot notes!
  if (comments.isEmpty) {
    final double x = colX[0];
    ctx.fillStyle = '#0F172A'.toJS;
    ctx.font = '900 34px "Arimo", "Segoe UI", Arial, sans-serif';
    ctx.fillText('NO ONLINE COMMENTS YET', x, colTop + 40);

    ctx.fillStyle = '#475569'.toJS;
    ctx.font = 'italic 30px Georgia, serif';
    ctx.fillText(
      'Be the first to leave a note at ${canonicalUrl.replaceFirst("https://", "")},',
      x,
      colTop + 96,
    );
    ctx.fillText(
      'or write your own margin notes below before passing this sheet on:',
      x,
      colTop + 140,
    );
    cursorY = colTop + 220;
  }

  // Fill remaining space in current column (and column 2 if column 1 was empty) with note lines
  for (int cIdx = colIdx; cIdx <= 1; cIdx++) {
    double startY = (cIdx == colIdx) ? math.max(cursorY + 30, colTop) : colTop;
    if (colBottom - startY < 260) continue;

    final double x = colX[cIdx];
    ctx.fillStyle = '#334155'.toJS;
    ctx.font = '900 26px "Arimo", "Segoe UI", Arial, sans-serif';
    ctx.fillText('MARGINALIA & HANDWRITTEN NOTES', x, startY + 28);
    startY += 86;

    ctx.strokeStyle = '#CBD5E1'.toJS;
    ctx.lineWidth = 2.0;
    while (startY < colBottom - 20) {
      ctx.beginPath();
      ctx.moveTo(x, startY);
      ctx.lineTo(x + colWidth, startY);
      ctx.stroke();
      startY += 88;
    }
  }

  // Footer Colophon
  ctx.fillStyle = '#F1F5F9'.toJS;
  ctx.fillRect(12, 3116, w - 24, 72);
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 6.0;
  ctx.beginPath();
  ctx.moveTo(12, 3116);
  ctx.lineTo(w - 12, 3116);
  ctx.stroke();

  ctx.fillStyle = '#1E293B'.toJS;
  ctx.font = 'bold 26px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(
    'JOIN THE DISCUSSION: ${canonicalUrl.replaceFirst("https://", "")}',
    64,
    3162,
  );
}

String _resolveCommentAuthor(Map<String, dynamic> c) {
  final String display = (c['displayName'] ?? c['authorName'] ?? '').toString().trim();
  final String handle = (c['username'] ?? c['authorHandle'] ?? '').toString().trim();
  if (display.isNotEmpty && handle.isNotEmpty) {
    return '$display (@${handle.replaceAll("@", "")})';
  }
  if (display.isNotEmpty) return display;
  if (handle.isNotEmpty) return '@${handle.replaceAll("@", "")}';
  return 'Archival Reader';
}

String _resolveCommentMeta(Map<String, dynamic> c) {
  final parts = <String>[];
  final String loc = (c['authorLocation'] ?? c['location'] ?? '').toString().trim();
  if (loc.isNotEmpty) parts.add(loc);
  final String dateStr = (c['letterDate'] ?? '').toString().trim();
  if (dateStr.isNotEmpty) parts.add(dateStr);
  if (c['sourceType'] == 'letter_column') parts.add('Letter Column');
  return parts.join(' · ');
}

/// Renders a vintage Zine / BQOPD House Ad plate when no separate scanned ad is selected.
void _drawHouseAdPage(
  web.CanvasRenderingContext2D ctx, {
  required String fanzineTitle,
  String? headline,
  String? body,
  String? indicia,
  required String canonicalUrl,
  required String shortCode,
}) {
  const double w = 2000.0;
  const double h = 3200.0;

  ctx.fillStyle = '#FFFDF7'.toJS;
  ctx.fillRect(0, 0, w, h);

  // Classic vintage zine double border
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 18.0;
  ctx.strokeRect(28, 28, w - 56, h - 56);
  ctx.lineWidth = 5.0;
  ctx.strokeRect(62, 62, w - 124, h - 124);

  // Top ornamental banner
  ctx.fillStyle = '#000000'.toJS;
  ctx.fillRect(110, 120, w - 220, 130);
  ctx.fillStyle = '#F1B255'.toJS;
  ctx.textAlign = 'center';
  ctx.font = '900 54px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('★  BQOPD FANZINE ARCHIVE & PRESS  ★', w / 2.0, 204);

  // Display Headline
  final String mainTitle = (headline != null && headline.trim().isNotEmpty)
      ? headline.trim().toUpperCase()
      : (fanzineTitle.trim().isNotEmpty
            ? fanzineTitle.trim().toUpperCase()
            : 'INDEPENDENT PRINT & DIGITAL ZINES');

  ctx.fillStyle = '#0F172A'.toJS;
  final titleLines = _wrapCanvasText(
    ctx,
    mainTitle,
    maxWidth: 1640,
    font: '900 104px "Impact", "Anton", "Arial Black", sans-serif',
  );
  ctx.font = '900 104px "Impact", "Anton", "Arial Black", sans-serif';
  double y = 430.0;
  for (final line in titleLines.take(4)) {
    ctx.fillText(line, w / 2.0, y);
    y += 120.0;
  }

  // Ornamental rule
  y += 30.0;
  ctx.fillStyle = '#000000'.toJS;
  ctx.fillRect(260, y, w - 520, 10);
  y += 110.0;

  // Subhead Pitch
  ctx.fillStyle = '#1E293B'.toJS;
  ctx.font = 'bold 46px Georgia, "Times New Roman", serif';
  ctx.fillText('READ · COLLECT · PRINT · PASS TO A FRIEND', w / 2.0, y);
  y += 110.0;

  // Body copy box
  final String copyText = (body != null && body.trim().isNotEmpty)
      ? body.trim()
      : 'Every page on bqopd is formatted for real half-letter saddle-stitch print spreads. '
            'Pin this sheet to your studio wall, fold it into a pocket folio, or hand it to a fellow reader.';

  final copyLines = _wrapCanvasText(
    ctx,
    copyText,
    maxWidth: 1520,
    font: '40px Georgia, "Times New Roman", serif',
  );
  ctx.font = '40px Georgia, "Times New Roman", serif';
  ctx.fillStyle = '#334155'.toJS;
  for (final line in copyLines.take(8)) {
    ctx.fillText(line, w / 2.0, y);
    y += 58.0;
  }

  // Featured coupon / callout frame
  const double boxY = 2060.0;
  const double boxH = 620.0;
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 8.0;
  ctx.setLineDash([20.0.toJS, 14.0.toJS].toJS);
  ctx.strokeRect(160, boxY, w - 320, boxH);
  ctx.setLineDash(<JSNumber>[].toJS);

  ctx.fillStyle = '#0F172A'.toJS;
  ctx.font = '900 44px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText('READ THIS ISSUE & EXPLORE THE ARCHIVE ONLINE', w / 2.0, boxY + 130);

  final String cleanUrl = canonicalUrl.replaceFirst('https://', '');
  ctx.fillStyle = '#6750A4'.toJS;
  ctx.font = '900 74px "Courier New", Courier, monospace';
  ctx.fillText(cleanUrl, w / 2.0, boxY + 290);

  ctx.fillStyle = '#475569'.toJS;
  ctx.font = 'bold 34px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(
    'UPLOAD YOUR OWN FOLIOS, ART, COMICS & LETTERS AT BQOPD.COM',
    w / 2.0,
    boxY + 440,
  );

  if (indicia != null && indicia.trim().isNotEmpty) {
    final indLines = _wrapCanvasText(
      ctx,
      indicia.trim(),
      maxWidth: 1600,
      font: '26px Georgia, serif',
    );
    ctx.fillStyle = '#64748B'.toJS;
    ctx.font = '26px Georgia, serif';
    double iy = 2830.0;
    for (final line in indLines.take(4)) {
      ctx.fillText(line, w / 2.0, iy);
      iy += 38.0;
    }
  }

  ctx.textAlign = 'left';
}

/// Renders a classic storefront "BUSINESS HOURS" door sign in native 2000 x 3200 space.
void _drawBusinessHoursPage(
  web.CanvasRenderingContext2D ctx, {
  required BusinessHoursSignData? sign,
  required String canonicalUrl,
}) {
  const double w = 2000.0;
  const double h = 3200.0;

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.fillRect(0, 0, w, h);

  // Classic front-door placard double black frame
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 20.0;
  ctx.strokeRect(30, 30, w - 60, h - 60);
  ctx.lineWidth = 6.0;
  ctx.strokeRect(66, 66, w - 132, h - 132);

  // Top "BUSINESS HOURS" banner (y = 116..366)
  ctx.fillStyle = '#111111'.toJS;
  ctx.fillRect(116, 116, w - 232, 250);

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  ctx.font = '900 118px "Impact", "Anton", "Arial Black", sans-serif';
  ctx.fillText('BUSINESS HOURS', w / 2.0, 286);

  // 3-Column Hours Table Geometry (x = 116..1884, width = 1768)
  const double tableLeft = 116.0;
  const double tableRight = 1884.0;
  const double tableWidth = tableRight - tableLeft;
  const double col1Right = 836.0; // Day of week column (width = 720)
  const double col2Right = 1360.0; // Open column (width = 524)
  // Close column: 1360..1884 (width = 524)

  const double headerTop = 410.0;
  const double headerBottom = 510.0;

  // Table header background
  ctx.fillStyle = '#F1F5F9'.toJS;
  ctx.fillRect(tableLeft, headerTop, tableWidth, headerBottom - headerTop);

  // Header labels: DAY | OPEN | CLOSE
  ctx.fillStyle = '#0F172A'.toJS;
  ctx.font = '900 38px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText('DAY', tableLeft + 36, headerTop + 66);

  ctx.textAlign = 'center';
  ctx.fillText('OPEN', (col1Right + col2Right) / 2.0, headerTop + 66);
  ctx.fillText('CLOSE', (col2Right + tableRight) / 2.0, headerTop + 66);

  // Top & header horizontal rules
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 8.0;
  ctx.beginPath();
  ctx.moveTo(tableLeft, headerTop);
  ctx.lineTo(tableRight, headerTop);
  ctx.moveTo(tableLeft, headerBottom);
  ctx.lineTo(tableRight, headerBottom);
  ctx.stroke();

  final List<BusinessHoursRowData> rows =
      (sign != null && sign.rows.isNotEmpty)
          ? sign.rows
          : const [
              BusinessHoursRowData(
                dayLabel: 'Monday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Tuesday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Wednesday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Thursday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Friday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Saturday',
                isOpen: false,
                open: '',
                close: '',
              ),
              BusinessHoursRowData(
                dayLabel: 'Sunday',
                isOpen: false,
                open: '',
                close: '',
              ),
            ];

  const double rowHeight = 220.0;
  final double rowsBottom = headerBottom + rows.length * rowHeight;

  for (int i = 0; i < rows.length; i++) {
    final row = rows[i];
    final double rTop = headerBottom + i * rowHeight;
    final double rBaseline = rTop + 130.0;

    // Subtle alternating zebra tint for quick legibility through glass doors
    if (i.isOdd) {
      ctx.fillStyle = '#F8FAFC'.toJS;
      ctx.fillRect(tableLeft, rTop, tableWidth, rowHeight);
    }

    // Column 1: Day of the week
    ctx.textAlign = 'left';
    ctx.fillStyle = '#0F172A'.toJS;
    ctx.font = '900 54px "Arimo", "Segoe UI", Arial, sans-serif';
    ctx.fillText(row.dayLabel.toUpperCase(), tableLeft + 36, rBaseline);

    // Column 2: Open time (or CLOSED)
    // Column 3: Close time (or —)
    final String openText = row.isOpen
        ? (row.open.trim().isNotEmpty ? row.open.trim() : 'OPEN')
        : 'CLOSED';
    final String closeText = row.isOpen
        ? (row.close.trim().isNotEmpty ? row.close.trim() : '—')
        : '—';

    ctx.textAlign = 'center';
    if (row.isOpen) {
      ctx.fillStyle = '#0F172A'.toJS;
      ctx.font = 'bold 50px "Arimo", "Segoe UI", Arial, sans-serif';
    } else {
      ctx.fillStyle = '#64748B'.toJS;
      ctx.font = '900 46px "Arimo", "Segoe UI", Arial, sans-serif';
    }
    ctx.fillText(openText, (col1Right + col2Right) / 2.0, rBaseline);
    ctx.fillText(closeText, (col2Right + tableRight) / 2.0, rBaseline);

    // Row divider
    ctx.strokeStyle = (i == rows.length - 1) ? '#000000'.toJS : '#CBD5E1'.toJS;
    ctx.lineWidth = (i == rows.length - 1) ? 10.0 : 3.0;
    ctx.beginPath();
    ctx.moveTo(tableLeft, rTop + rowHeight);
    ctx.lineTo(tableRight, rTop + rowHeight);
    ctx.stroke();
  }

  // Outer left/right & internal vertical column dividers for the 3-column table
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 6.0;
  ctx.beginPath();
  ctx.moveTo(tableLeft, headerTop);
  ctx.lineTo(tableLeft, rowsBottom);
  ctx.moveTo(tableRight, headerTop);
  ctx.lineTo(tableRight, rowsBottom);
  ctx.stroke();

  ctx.strokeStyle = '#CBD5E1'.toJS;
  ctx.lineWidth = 3.5;
  ctx.beginPath();
  ctx.moveTo(col1Right, headerTop);
  ctx.lineTo(col1Right, rowsBottom);
  ctx.moveTo(col2Right, headerTop);
  ctx.lineTo(col2Right, rowsBottom);
  ctx.stroke();

  // Business Identity Block underneath the hours (y = 2160..3040)
  double cursorY = rowsBottom + 130.0;
  ctx.textAlign = 'center';

  // 1. Display Name
  final String displayName =
      (sign != null && sign.displayName.trim().isNotEmpty)
          ? sign.displayName.trim().toUpperCase()
          : 'BUSINESS';
  final List<String> nameLines = _wrapCanvasText(
    ctx,
    displayName,
    maxWidth: 1680,
    font: '900 84px "Impact", "Anton", "Arial Black", sans-serif',
  );
  ctx.fillStyle = '#0F172A'.toJS;
  ctx.font = '900 84px "Impact", "Anton", "Arial Black", sans-serif';
  for (final line in nameLines.take(2)) {
    ctx.fillText(line, w / 2.0, cursorY);
    cursorY += 96.0;
  }

  // 2. @handle
  final String cleanHandle =
      (sign?.username ?? '').trim().replaceAll('@', '');
  if (cleanHandle.isNotEmpty) {
    cursorY += 6.0;
    ctx.fillStyle = '#4338CA'.toJS;
    ctx.font = '900 50px "Courier New", Courier, monospace';
    ctx.fillText('@$cleanHandle', w / 2.0, cursorY);
    cursorY += 72.0;
  } else {
    cursorY += 24.0;
  }

  // Ornamental rule between handle and mailing address
  ctx.fillStyle = '#000000'.toJS;
  ctx.fillRect(w / 2.0 - 220, cursorY - 24, 440, 6);
  cursorY += 48.0;

  // 3. Mailing Address
  final List<String> addrLines = sign?.addressLines ?? const [];
  if (addrLines.isNotEmpty) {
    ctx.fillStyle = '#1E293B'.toJS;
    for (final rawAddr in addrLines) {
      final wrapped = _wrapCanvasText(
        ctx,
        rawAddr,
        maxWidth: 1640,
        font: 'bold 44px "Arimo", "Segoe UI", Arial, sans-serif',
      );
      ctx.font = 'bold 44px "Arimo", "Segoe UI", Arial, sans-serif';
      for (final line in wrapped) {
        if (cursorY > 3040) break;
        ctx.fillText(line, w / 2.0, cursorY);
        cursorY += 58.0;
      }
    }
  }

  // Subtle bottom colophon inside inner border
  ctx.fillStyle = '#64748B'.toJS;
  ctx.font = 'bold 24px "Arimo", "Segoe UI", Arial, sans-serif';
  ctx.fillText(
    canonicalUrl.replaceFirst('https://', ''),
    w / 2.0,
    3100,
  );

  ctx.textAlign = 'left';
}

/// Fallback renderer for text-only pages that haven't been rasterized to an image yet.
void _drawFallbackTextPage(
  web.CanvasRenderingContext2D ctx, {
  required String title,
  required String body,
  required String canonicalUrl,
}) {
  const double w = 2000.0;
  const double h = 3200.0;

  ctx.fillStyle = '#FFFFFF'.toJS;
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#000000'.toJS;
  ctx.lineWidth = 11.0;
  ctx.strokeRect(5.5, 5.5, w - 11, h - 11);

  // 3-column rules matching bqopd publisher page geometry
  ctx.fillStyle = '#000000'.toJS;
  ctx.fillRect(663, 99, 11, h - 198);
  ctx.fillRect(1326, 99, 11, h - 198);

  const List<double> colsX = [33.0, 696.0, 1359.0];
  const double colW = 608.0;
  int col = 0;
  double y = 90.0;

  ctx.font = '900 38px "Impact", "Arial Black", sans-serif';
  final headLines = _wrapCanvasText(
    ctx,
    title.toUpperCase(),
    maxWidth: colW,
    font: '900 38px "Impact", "Arial Black", sans-serif',
  );
  for (final l in headLines) {
    ctx.fillText(l, colsX[col], y);
    y += 46.0;
  }
  y += 28.0;

  final String cleanBody = body
      .replaceAll(RegExp(r'[#*`]+'), '')
      .trim();
  final paragraphs = cleanBody.isEmpty ? [canonicalUrl] : cleanBody.split('\n');

  ctx.font = '28px Georgia, serif';
  ctx.fillStyle = '#1E293B'.toJS;
  for (final p in paragraphs) {
    if (p.trim().isEmpty) {
      y += 24.0;
      continue;
    }
    final lines = _wrapCanvasText(
      ctx,
      p.trim(),
      maxWidth: colW,
      font: '28px Georgia, serif',
    );
    for (final line in lines) {
      if (y > 3060) {
        col++;
        y = 90.0;
        if (col >= 3) return;
      }
      ctx.fillText(line, colsX[col], y);
      y += 38.0;
    }
    y += 18.0;
  }
}

List<String> _wrapCanvasText(
  web.CanvasRenderingContext2D ctx,
  String text, {
  required double maxWidth,
  required String font,
}) {
  ctx.font = font;
  final words = text.split(RegExp(r'\s+'));
  final List<String> lines = [];
  String current = '';

  for (final word in words) {
    if (word.isEmpty) continue;
    final String candidate = current.isEmpty ? word : '$current $word';
    if (ctx.measureText(candidate).width > maxWidth && current.isNotEmpty) {
      lines.add(current);
      current = word;
    } else {
      current = candidate;
    }
  }
  if (current.isNotEmpty) {
    lines.add(current);
  }
  return lines;
}
