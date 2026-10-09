@JS()
library web_firebase_interop_web;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'web_firebase_interop.dart';

/// Web implementation of the subscription wrapper to bridge the JS unsubscription callback.
class WebSubscription implements FirebaseSubscription {
  final JSFunction _jsFunction;
  WebSubscription(this._jsFunction);

  @override
  void callAsFunction() {
    _jsFunction.callAsFunction();
  }
}

@JS('getCurrentUserId')
external JSString? _getCurrentUserId();
String? getCurrentUserId() => _getCurrentUserId()?.toDart;

@JS('fsGetDoc')
external JSPromise _fsGetDoc(JSString path);
Future<String> fsGetDoc(String path) async {
  final jsRes = await _fsGetDoc(path.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsListenDoc')
external JSFunction _fsListenDoc(JSString path, JSFunction callback);
FirebaseSubscription fsListenDoc(String path, void Function(String) callback) {
  final jsFunc = _fsListenDoc(path.toJS, ((JSString str) => callback(str.toDart)).toJS);
  return WebSubscription(jsFunc);
}

@JS('fsListenQuery')
external JSFunction _fsListenQuery(
    JSString path,
    JSString field,
    JSString op,
    JSString valueJson,
    JSString orderBy,
    JSBoolean desc,
    JSFunction callback);
FirebaseSubscription fsListenQuery(
    String path,
    String field,
    String op,
    String valueJson,
    String orderBy,
    bool desc,
    void Function(String) callback) {
  final jsFunc = _fsListenQuery(
      path.toJS,
      field.toJS,
      op.toJS,
      valueJson.toJS,
      orderBy.toJS,
      desc.toJS,
      ((JSString str) => callback(str.toDart)).toJS);
  return WebSubscription(jsFunc);
}

@JS('fsUpdateDoc')
external JSPromise _fsUpdateDoc(JSString path, JSString dataJson);
Future<void> fsUpdateDoc(String path, String dataJson) async {
  await _fsUpdateDoc(path.toJS, dataJson.toJS).toDart;
}

@JS('fsSetDoc')
external JSPromise _fsSetDoc(JSString path, JSString dataJson, JSBoolean merge);
Future<void> fsSetDoc(String path, String dataJson, bool merge) async {
  await _fsSetDoc(path.toJS, dataJson.toJS, merge.toJS).toDart;
}

@JS('fsDeleteDoc')
external JSPromise _fsDeleteDoc(JSString path);
Future<void> fsDeleteDoc(String path) async {
  await _fsDeleteDoc(path.toJS).toDart;
}

@JS('fsAddDoc')
external JSPromise _fsAddDoc(JSString path, JSString dataJson);
Future<String> fsAddDoc(String path, String dataJson) async {
  final jsRes = await _fsAddDoc(path.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsQuery')
external JSPromise _fsQuery(
    JSString path, JSString field, JSString op, JSString valueJson, JSString orderBy);
Future<String> fsQuery(
    String path, String field, String op, String valueJson, String orderBy) async {
  final jsRes = await _fsQuery(
      path.toJS, field.toJS, op.toJS, valueJson.toJS, orderBy.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fnCall')
external JSPromise _fnCall(JSString name, JSString dataJson);
Future<String> fnCall(String name, String dataJson) async {
  final jsRes = await _fnCall(name.toJS, dataJson.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('stUpload')
external JSPromise _stUpload(JSString path, JSUint8Array bytes, JSString contentType);
Future<String> stUpload(String path, Uint8List bytes, String contentType) async {
  final jsRes = await _stUpload(path.toJS, bytes.toJS, contentType.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('onAuthStateChangedListener')
external void _onAuthStateChangedListener(JSFunction callback);
void onAuthStateChangedListener(void Function(String?, String?) callback) {
  _onAuthStateChangedListener(((JSString? uid, JSString? email) {
    callback(uid?.toDart, email?.toDart);
  }).toJS);
}

@JS('loginWithFirebase')
external JSPromise _loginWithFirebase(JSString email, JSString password);
Future<void> loginWithFirebase(String email, String password) async {
  await _loginWithFirebase(email.toJS, password.toJS).toDart;
}

@JS('registerWithFirebase')
external JSPromise _registerWithFirebase(
    JSString email, JSString password, JSString username);
Future<void> registerWithFirebase(
    String email, String password, String username) async {
  await _registerWithFirebase(email.toJS, password.toJS, username.toJS).toDart;
}

@JS('logoutFromFirebase')
external JSPromise _logoutFromFirebase();
Future<void> logoutFromFirebase() async {
  await _logoutFromFirebase().toDart;
}

@JS('pickAndReadFile')
external void _pickAndReadFile(JSString inputId, JSFunction callback);
void pickAndReadFile(
    String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  _pickAndReadFile(inputId.toJS,
      ((JSString base64, JSString fileName, JSString objectUrl) {
        callback(base64.toDart, fileName.toDart, objectUrl.toDart);
      }).toJS);
}

@JS('readInputFile')
external void _readInputFile(JSString inputId, JSFunction callback);
void readInputFile(
    String inputId, void Function(String base64, String fileName, String objectUrl) callback) {
  _readInputFile(inputId.toJS,
      ((JSString base64, JSString fileName, JSString objectUrl) {
        callback(base64.toDart, fileName.toDart, objectUrl.toDart);
      }).toJS);
}

@JS('renderPublisherPage')
external JSPromise _renderPublisherPage(JSString text);
Future<String> renderPublisherPage(String text) async {
  try {
    final jsRes = await _renderPublisherPage(text.toJS).toDart;
    return (jsRes as JSString).toDart;
  } catch (e) {
    print('[renderPublisherPage Error] $e');
    rethrow;
  }
}

/// Dynamically injects and polyfills [window.renderPublisherPages] directly into
/// the browser document if missing, preventing NoSuchMethodError caused by cached JS.
void _ensureRenderPublisherPagesScript() {
  final jsWin = web.window as JSObject;
  if (jsWin.has('renderPublisherPages')) {
    final fn = jsWin['renderPublisherPages'];
    if (fn != null) return;
  }

  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.id = 'dynamic-render-publisher-pages-polyfill';
  script.text = r'''
window.renderPublisherPages = async (text) => {
    const pagesResults = [];

    function initPageCanvas() {
        const c = document.createElement('canvas');
        c.width = 2000;
        c.height = 3200;
        const context = c.getContext('2d');
        context.fillStyle = '#ffffff';
        context.fillRect(0, 0, 2000, 3200);
        context.lineWidth = 11;
        context.strokeStyle = '#000000';
        context.strokeRect(5.5, 5.5, 2000 - 11, 3200 - 11);
        context.fillStyle = '#000000';
        context.fillRect(663, 99, 11, 3200 - 198);
        context.fillRect(1326, 99, 11, 3200 - 198);
        return { canvas: c, ctx: context };
    }

    let active = initPageCanvas();
    let canvas = active.canvas;
    let ctx = active.ctx;

    const columnsX = [33, 696, 1359];
    const colWidth = 608;
    const maxY = 3120;

    let colIndex = 0;
    let currentY = 33;
    let currentPageTextParts = [];

    function wrapText(textToWrap, fontSize, fontName, bold) {
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px ${fontName}`;
        const words = textToWrap.split(' ');
        const lines = [];
        let currentLine = "";

        for (let word of words) {
            const testLine = currentLine ? currentLine + " " + word : word;
            if (ctx.measureText(testLine).width > colWidth) {
                lines.push(currentLine);
                currentLine = word;
            } else {
                currentLine = testLine;
            }
        }
        if (currentLine) lines.push(currentLine);
        return lines;
    }

    function loadImage(url) {
        return new Promise((resolve) => {
            const img = new Image();
            if (url.startsWith('http://') || url.startsWith('https://')) {
                img.crossOrigin = "anonymous";
            }
            img.onload = () => resolve(img);
            img.onerror = () => resolve(null);
            img.src = url;
        });
    }

    function finalizeCurrentPage() {
        function getScaledBase64(targetWidth, targetHeight) {
            const scaledCanvas = document.createElement('canvas');
            scaledCanvas.width = targetWidth;
            scaledCanvas.height = targetHeight;
            const sCtx = scaledCanvas.getContext('2d');
            sCtx.drawImage(canvas, 0, 0, 2000, 3200, 0, 0, targetWidth, targetHeight);
            return scaledCanvas.toDataURL('image/webp', 0.8).split(',')[1];
        }

        const originalBase64 = canvas.toDataURL('image/webp', 0.9).split(',')[1];
        const listBase64 = getScaledBase64(800, 1280);
        const gridBase64 = getScaledBase64(450, 720);
        const pageText = currentPageTextParts.join('\n\n').trim();

        pagesResults.push({
            original: originalBase64,
            list: listBase64,
            grid: gridBase64,
            text: pageText
        });

        active = initPageCanvas();
        canvas = active.canvas;
        ctx = active.ctx;
        colIndex = 0;
        currentY = 33;
        currentPageTextParts = [];
    }

    function advanceToNextColumn() {
        colIndex++;
        currentY = 33;
        if (colIndex >= 3) {
            finalizeCurrentPage();
        }
    }

    const lines = text.split('\n');
    const blocks = [];
    let currentParagraph = "";

    function commitParagraph() {
        const pText = currentParagraph.trim();
        if (!pText) return;

        const imageRegex = /^\{\{IMAGE(?::\s*(.*?))?\}\}$/i;
        const templateRegex = /^\{\{TEMPLATE_(\d+):\s*([^|]+)\s*\|\s*(.*?)\}\}$/i;
        const colBreakRegex = /^(?:\{\{|\[\[)COLUMN_BREAK(?:\}\}|\]\])$/i;

        const match = imageRegex.exec(pText);
        const tMatch = templateRegex.exec(pText);
        const cbMatch = colBreakRegex.exec(pText);

        if (match) {
            blocks.push({ type: 'image', url: match[1] ? match[1].trim() : '' });
        } else if (tMatch) {
            let targetRow = null;
            let captionText = tMatch[3].trim();
            const rowMatch = /^row=(\d+)\s*\|\s*(.*)$/i.exec(captionText);
            if (rowMatch) {
                targetRow = parseInt(rowMatch[1]);
                captionText = rowMatch[2].trim();
            }

            blocks.push({ type: 'column_break' });
            blocks.push({
                type: 'template_block',
                templateNum: parseInt(tMatch[1]),
                url: tMatch[2].trim(),
                content: captionText,
                targetRow: targetRow
            });
            blocks.push({ type: 'column_break' });
        } else if (cbMatch || pText.toLowerCase() === 'column-break' || pText.toLowerCase() === 'column_break') {
            blocks.push({ type: 'column_break' });
        } else if (pText.startsWith('###')) {
            blocks.push({ type: 'h3', content: pText.substring(3).trim(), raw: pText });
        } else if (pText.startsWith('##')) {
            blocks.push({ type: 'h2', content: pText.substring(2).trim(), raw: pText });
        } else if (pText.startsWith('#')) {
            blocks.push({ type: 'h1', content: pText.substring(1).trim(), raw: pText });
        } else if (pText.startsWith('* ') || pText.startsWith('- ')) {
            blocks.push({ type: 'bullet', content: pText.substring(2).trim(), raw: pText });
        } else {
            blocks.push({ type: 'text', content: pText, raw: pText });
        }
        currentParagraph = "";
    }

    for (let line of lines) {
        const cleanLine = line.trim();
        if (cleanLine === "") {
            commitParagraph();
        } else if (cleanLine.startsWith('#') || cleanLine.startsWith('*') || cleanLine.startsWith('-') || cleanLine.startsWith('{{') || cleanLine.startsWith('[[')) {
            commitParagraph();
            currentParagraph = cleanLine;
            commitParagraph();
        } else {
            currentParagraph = currentParagraph ? currentParagraph + " " + cleanLine : cleanLine;
        }
    }
    commitParagraph();

    for (let block of blocks) {
        if (block.type === 'column_break') {
            if (currentY > 33) {
                advanceToNextColumn();
            }
            continue;
        }

        if (block.type === 'image') {
            const targetUrl = block.url;
            let img = null;
            if (targetUrl && targetUrl.trim().length > 0) {
                img = await loadImage(targetUrl);
            }

            let drawHeight = 400;
            if (img && img.width > 0 && img.height > 0) {
                drawHeight = colWidth * (img.height / img.width);
            }

            if (currentY + drawHeight > maxY) {
                advanceToNextColumn();
            }

            if (img) {
                ctx.drawImage(img, columnsX[colIndex], currentY, colWidth, drawHeight);
            } else {
                ctx.fillStyle = '#f3f4f6';
                ctx.fillRect(columnsX[colIndex], currentY, colWidth, drawHeight);
                ctx.lineWidth = 4;
                ctx.strokeStyle = '#d1d5db';
                ctx.strokeRect(columnsX[colIndex] + 10, currentY + 10, colWidth - 20, drawHeight - 20);
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(columnsX[colIndex] + 10, currentY + 10);
                ctx.lineTo(columnsX[colIndex] + colWidth - 10, currentY + drawHeight - 10);
                ctx.moveTo(columnsX[colIndex] + colWidth - 10, currentY + 10);
                ctx.lineTo(columnsX[colIndex] + 10, currentY + drawHeight - 10);
                ctx.stroke();
                ctx.font = 'bold 24px Arial';
                ctx.fillStyle = '#9ca3af';
                ctx.textAlign = 'center';
                ctx.fillText('Image Asset Placeholder', columnsX[colIndex] + colWidth / 2, currentY + drawHeight / 2);
                ctx.textAlign = 'left';
            }

            currentY += drawHeight + 20;
            currentPageTextParts.push(`{{IMAGE: ${targetUrl}}}`);

        } else if (block.type === 'template_block' && block.templateNum === 1) {
            const targetUrl = block.url;
            let img = null;
            if (targetUrl && targetUrl.trim().length > 0) {
                img = await loadImage(targetUrl);
            }

            let imgHeight = 400;
            if (img && img.width > 0 && img.height > 0) {
                imgHeight = colWidth * (img.height / img.width);
            }

            const fontSize = 24;
            const fontName = 'Arial';
            const linesToDraw = wrapText(block.content, fontSize, fontName, false);
            const textLeadingStep = fontSize * 1.4;
            const totalTextHeight = linesToDraw.length * textLeadingStep + 12;

            if (block.targetRow !== null && block.targetRow !== undefined) {
                let targetYBottom = 33 + block.targetRow * 42;
                let targetYTop = targetYBottom - imgHeight;

                if (currentY > targetYTop || targetYBottom + totalTextHeight > maxY) {
                    advanceToNextColumn();
                    targetYBottom = 33 + block.targetRow * 42;
                    targetYTop = targetYBottom - imgHeight;
                }

                if (img) {
                    ctx.drawImage(img, columnsX[colIndex], targetYTop, colWidth, imgHeight);
                } else {
                    ctx.fillStyle = '#f3f4f6';
                    ctx.fillRect(columnsX[colIndex], targetYTop, colWidth, imgHeight);
                }
                currentY = targetYTop + imgHeight + 16;

                ctx.font = `${fontSize}px ${fontName}`;
                ctx.fillStyle = '#1a1a1a';
                for (let line of linesToDraw) {
                    ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                    currentY += textLeadingStep;
                }
                currentY += 24;
            } else {
                const compositeBlockHeight = imgHeight + totalTextHeight + 20;
                if (currentY + compositeBlockHeight > maxY) {
                    advanceToNextColumn();
                }

                if (img) {
                    ctx.drawImage(img, columnsX[colIndex], currentY, colWidth, imgHeight);
                } else {
                    ctx.fillStyle = '#f3f4f6';
                    ctx.fillRect(columnsX[colIndex], currentY, colWidth, imgHeight);
                }
                currentY += imgHeight + 16;

                ctx.font = `${fontSize}px ${fontName}`;
                ctx.fillStyle = '#1a1a1a';
                for (let line of linesToDraw) {
                    ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                    currentY += textLeadingStep;
                }
                currentY += 24;
            }
            currentPageTextParts.push(`{{TEMPLATE_1: ${targetUrl} | ${block.content}}}`);

        } else {
            let fontSize, fontName, bold = false, heightMultiplier = 1.5, spaceBelow = 12;
            if (block.type === 'h1') {
                fontSize = 42; fontName = 'Impact'; bold = true; heightMultiplier = 1.25; spaceBelow = 16;
            } else if (block.type === 'h2') {
                fontSize = 36; fontName = 'Impact'; bold = true; heightMultiplier = 1.25; spaceBelow = 14;
            } else if (block.type === 'h3') {
                fontSize = 28; fontName = 'Impact'; bold = true; heightMultiplier = 1.25; spaceBelow = 12;
            } else {
                fontSize = 28; fontName = 'Arial'; heightMultiplier = 1.5; spaceBelow = 12;
            }

            const isBullet = block.type === 'bullet';
            const textToWrap = isBullet ? "•  " + block.content : block.content;
            const linesToDraw = wrapText(textToWrap, fontSize, fontName, bold);

            ctx.font = `${bold ? 'bold ' : ''}${fontSize}px ${fontName}`;
            ctx.fillStyle = '#1a1a1a';

            const step = fontSize * heightMultiplier;
            let currentParagraphRenderedLines = [];

            for (let i = 0; i < linesToDraw.length; i++) {
                const line = linesToDraw[i];
                if (currentY + fontSize > maxY) {
                    if (currentParagraphRenderedLines.length > 0) {
                        currentPageTextParts.push(currentParagraphRenderedLines.join(' '));
                        currentParagraphRenderedLines = [];
                    }
                    advanceToNextColumn();
                    ctx.font = `${bold ? 'bold ' : ''}${fontSize}px ${fontName}`;
                    ctx.fillStyle = '#1a1a1a';
                }

                const isLastLine = i === linesToDraw.length - 1;
                if (!isLastLine && block.type === 'text' && linesToDraw.length > 1) {
                    const words = line.split(' ');
                    if (words.length > 1) {
                        let wordsWidth = 0;
                        for (let word of words) wordsWidth += ctx.measureText(word).width;
                        const wordSpacing = (colWidth - wordsWidth) / (words.length - 1);

                        let currentX = columnsX[colIndex];
                        for (let word of words) {
                            ctx.fillText(word, currentX, currentY + fontSize);
                            currentX += ctx.measureText(word).width + wordSpacing;
                        }
                    } else {
                        ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                    }
                } else {
                    ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                }
                currentY += step;
                currentParagraphRenderedLines.push(line);
            }
            currentY += spaceBelow;
            if (currentParagraphRenderedLines.length > 0) {
                if (block.type === 'h1') currentPageTextParts.push('# ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'h2') currentPageTextParts.push('## ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'h3') currentPageTextParts.push('### ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'bullet') currentPageTextParts.push('* ' + currentParagraphRenderedLines.join(' '));
                else currentPageTextParts.push(currentParagraphRenderedLines.join(' '));
            }
        }
    }

    if (currentY > 33 || colIndex > 0) {
        finalizeCurrentPage();
    }

    return JSON.stringify(pagesResults);
};
''';
  web.document.head?.append(script);
}

@JS('renderPublisherPages')
external JSPromise? _renderPublisherPages(JSString text);

Future<String> renderPublisherPages(String text) async {
  try {
    _ensureRenderPublisherPagesScript();
    final jsRes = await _renderPublisherPages(text.toJS)?.toDart;
    if (jsRes != null) {
      return (jsRes as JSString).toDart;
    }
  } catch (e) {
    print('[renderPublisherPages Polyfill Call] $e. Falling back to singular renderPublisherPage.');
  }

  // Graceful fallback to singular page compiler if the polyfill was delayed
  try {
    final single = await renderPublisherPage(text);
    return '[$single]';
  } catch (e) {
    print('[renderPublisherPages Fallback Error] $e');
    return '[]';
  }
}

@JS('getPlacePredictions')
external JSPromise _getPlacePredictions(JSString input);
Future<String> getPlacePredictions(String input) async {
  try {
    final jsRes = await _getPlacePredictions(input.toJS).toDart;
    return (jsRes as JSString).toDart;
  } catch (e) {
    print('[getPlacePredictions Error] $e');
    return '[]';
  }
}

@JS('geocodeAddress')
external JSPromise _geocodeAddress(JSString address);
Future<String?> geocodeAddress(String address) async {
  try {
    final jsRes = await _geocodeAddress(address.toJS).toDart;
    if (jsRes == null) return null;
    return (jsRes as JSString).toDart;
  } catch (e) {
    print('[geocodeAddress Error] $e');
    return null;
  }
}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num value) =>
      {'__op': 'increment', 'value': value};
  static Map<String, dynamic> arrayUnion(List values) =>
      {'__op': 'arrayUnion', 'values': values};
  static Map<String, dynamic> arrayRemove(List values) =>
      {'__op': 'arrayRemove', 'values': values};
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}