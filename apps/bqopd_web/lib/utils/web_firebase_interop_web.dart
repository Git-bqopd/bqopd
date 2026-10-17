@JS()
library web_firebase_interop_web;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'web_firebase_interop.dart';

class WebSubscription implements FirebaseSubscription {
  final JSFunction _jsFunction;
  WebSubscription(this._jsFunction);

  @override
  void callAsFunction() {
    _jsFunction.callAsFunction();
  }
}

@JS('renderMapCoverPage')
external JSPromise<JSString>? _renderMapCoverPage(JSString configJson);

void _ensureRenderMapCoverPageScript() {
  final jsWin = web.window as JSObject;
  if (jsWin.has('renderMapCoverPage')) {
    final fn = jsWin['renderMapCoverPage'];
    if (fn != null) return;
  }

  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.id = 'dynamic-render-map-cover-polyfill';
  script.text = r'''
window.renderMapCoverPage = async (configJson) => {
    const config = typeof configJson === 'string' ? JSON.parse(configJson) : configJson;
    const center = config.center || { lat: 43.8396, lng: -91.2436, address: "La Crosse, WI" };
    const letters = Array.isArray(config.letters) ? config.letters : [];
    const folioTitle = config.title || `Letters near ${center.address}`;
    const apiKey = (window.firebaseConfig && window.firebaseConfig.apiKey) || "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g";

    const canvas = document.createElement('canvas');
    canvas.width = 2000;
    canvas.height = 3200;
    const ctx = canvas.getContext('2d');

    ctx.fillStyle = '#e5e3df';
    ctx.fillRect(0, 0, 2000, 3200);

    const allCoords = [];
    if (center.lat != null && center.lng != null) {
        allCoords.push({ lat: Number(center.lat), lng: Number(center.lng), isCenter: true });
    }
    letters.forEach((l) => {
        const lat = parseFloat(l.lat);
        const lng = parseFloat(l.lng);
        if (!isNaN(lat) && !isNaN(lng)) {
            allCoords.push({
                lat: lat,
                lng: lng,
                isCenter: false
            });
        }
    });

    if (allCoords.length === 0) {
        allCoords.push({ lat: 43.8396, lng: -91.2436, isCenter: true });
    }

    let minLat = allCoords[0].lat, maxLat = allCoords[0].lat;
    let minLng = allCoords[0].lng, maxLng = allCoords[0].lng;
    allCoords.forEach(c => {
        if (c.lat < minLat) minLat = c.lat;
        if (c.lat > maxLat) maxLat = c.lat;
        if (c.lng < minLng) minLng = c.lng;
        if (c.lng > maxLng) maxLng = c.lng;
    });

    const latSpan = Math.max(0.02, maxLat - minLat);
    const lngSpan = Math.max(0.02, maxLng - minLng);
    minLat -= latSpan * 0.20;
    maxLat += latSpan * 0.20;
    minLng -= lngSpan * 0.20;
    maxLng += lngSpan * 0.20;

    const centerLat = (minLat + maxLat) / 2;
    const centerLng = (minLng + maxLng) / 2;

    function latToRad(lat) {
        const sin = Math.sin(lat * Math.PI / 180);
        return Math.log((1 + sin) / (1 - sin)) / 2;
    }

    function calculateZoom() {
        const latFraction = (latToRad(maxLat) - latToRad(minLat)) / Math.PI;
        const lngFraction = (maxLng - minLng) / 360;
        const latZoom = Math.floor(Math.log(3200 / 256 / Math.max(0.0001, latFraction)) / Math.LN2);
        const lngZoom = Math.floor(Math.log(2000 / 256 / Math.max(0.0001, lngFraction)) / Math.LN2);
        return Math.max(4, Math.min(14, Math.min(latZoom, lngZoom)));
    }

    const zoom = calculateZoom();

    function projectToWorld(lat, lng, z) {
        const scale = 256 * Math.pow(2, z);
        const x = (lng + 180) / 360 * scale;
        const sin = Math.sin(lat * Math.PI / 180);
        const y = (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * scale;
        return { x: x, y: y };
    }

    const centerWorld = projectToWorld(centerLat, centerLng, zoom);
    const originX = centerWorld.x - 1000;
    const originY = centerWorld.y - 1600;

    let mapLoaded = false;
    try {
        const fnResult = await functions.httpsCallable('fetch_static_map')({
            markers: allCoords.map(c => ({ lat: c.lat, lng: c.lng, isCenter: c.isCenter })),
            center: `${centerLat},${centerLng}`,
            zoom: zoom,
            width: 400,
            height: 640,
            scale: 2,
            api_key: apiKey
        });
        if (fnResult && fnResult.data && fnResult.data.status === 'success' && fnResult.data.data_url) {
            await new Promise((resolve) => {
                const img = new Image();
                img.onload = () => { ctx.drawImage(img, 0, 0, 2000, 3200); mapLoaded = true; resolve(); };
                img.onerror = () => resolve();
                img.src = fnResult.data.data_url;
            });
        }
    } catch (_) {}

    if (!mapLoaded) {
        const tileSize = 512;
        const minTileX = Math.floor(originX / tileSize);
        const maxTileX = Math.floor((originX + 2000) / tileSize);
        const minTileY = Math.floor(originY / tileSize);
        const maxTileY = Math.floor((originY + 3200) / tileSize);

        const subdomains = ['a', 'b', 'c', 'd'];
        const tilePromises = [];

        for (let tx = minTileX; tx <= maxTileX; tx++) {
            for (let ty = minTileY; ty <= maxTileY; ty++) {
                const sub = subdomains[Math.abs(tx + ty) % subdomains.length];
                const tileUrl = `https://${sub}.basemaps.cartocdn.com/rastertiles/voyager/${zoom}/${tx}/${ty}@2x.png`;
                const destX = tx * tileSize - originX;
                const destY = ty * tileSize - originY;

                tilePromises.push(new Promise((resolve) => {
                    const tImg = new Image();
                    tImg.crossOrigin = "anonymous";
                    tImg.onload = () => { ctx.drawImage(tImg, destX, destY, tileSize, tileSize); resolve(); };
                    tImg.onerror = () => resolve();
                    tImg.src = tileUrl;
                }));
            }
        }
        await Promise.all(tilePromises);
    }

    function drawPin(x, y, isCenter) {
        ctx.save();
        const scale = isCenter ? 1.25 : 1.0;
        const radius = 28 * scale;
        const pinHeight = 58 * scale;
        const headY = y - pinHeight;

        ctx.beginPath();
        ctx.ellipse(x + 4 * scale, y + 2 * scale, 15 * scale, 6.5 * scale, 0, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(0, 0, 0, 0.3)';
        ctx.fill();

        ctx.beginPath();
        ctx.arc(x, headY, radius, Math.PI * 0.18, Math.PI * 0.82, true);
        ctx.lineTo(x, y);
        ctx.closePath();

        ctx.fillStyle = isCenter ? '#b71c1c' : '#ea4335';
        ctx.fill();
        ctx.lineWidth = 3.5 * scale;
        ctx.strokeStyle = '#ffffff';
        ctx.stroke();

        if (isCenter) {
            ctx.beginPath();
            ctx.arc(x, headY, radius * 0.52, 0, Math.PI * 2);
            ctx.fillStyle = '#ffebee';
            ctx.fill();

            ctx.beginPath();
            ctx.arc(x, headY, radius * 0.24, 0, Math.PI * 2);
            ctx.fillStyle = '#b71c1c';
            ctx.fill();
        } else {
            ctx.beginPath();
            ctx.arc(x, headY, radius * 0.34, 0, Math.PI * 2);
            ctx.fillStyle = '#761214';
            ctx.fill();
        }

        ctx.restore();
    }

    allCoords.filter(c => !c.isCenter).forEach(c => {
        const pt = projectToWorld(c.lat, c.lng, zoom);
        drawPin(pt.x - originX, pt.y - originY, false);
    });

    const centerCoord = allCoords.find(c => c.isCenter);
    if (centerCoord) {
        const pt = projectToWorld(centerCoord.lat, centerCoord.lng, zoom);
        drawPin(pt.x - originX, pt.y - originY, true);
    }

    function getScaled(targetW, targetH) {
        const c = document.createElement('canvas');
        c.width = targetW; c.height = targetH;
        c.getContext('2d').drawImage(canvas, 0, 0, 2000, 3200, 0, 0, targetW, targetH);
        return c.toDataURL('image/webp', 0.8).split(',')[1];
    }

    return JSON.stringify({
        original: canvas.toDataURL('image/webp', 0.9).split(',')[1],
        list: getScaled(800, 1280),
        grid: getScaled(450, 720),
        text: `Map Cover: ${folioTitle}\nCenter: ${center.address}\nLetters: ${letters.length}`
    });
};
globalThis.renderMapCoverPage = window.renderMapCoverPage;
''';
  web.document.head?.append(script);
}

Future<String> renderMapCoverPage(String configJson) async {
  try {
    _ensureRenderMapCoverPageScript();
    final promise = _renderMapCoverPage(configJson.toJS);
    if (promise != null) {
      final jsResult = await promise.toDart;
      return jsResult.toDart;
    }
  } catch (e) {
    print('[renderMapCoverPage Error] $e');
  }
  return '{}';
}

void _ensureRenderPublisherPagesScript() {
  final jsWin = web.window as JSObject;
  if (jsWin.has('renderPublisherPages') && jsWin.has('measurePublisherPages')) {
    final fn = jsWin['renderPublisherPages'];
    if (fn != null) return;
  }

  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.id = 'dynamic-render-publisher-pages-polyfill';
  script.text = r'''
// Reusable scratch 2D context for zero-allocation text measurement
let _scratchMeasureCtx = null;
function getScratchMeasureCtx() {
    if (!_scratchMeasureCtx) {
        const c = document.createElement('canvas');
        c.width = 1;
        c.height = 1;
        _scratchMeasureCtx = c.getContext('2d');
    }
    return _scratchMeasureCtx;
}

window.measurePublisherPages = (text) => {
    if (!text || typeof text !== 'string' || !text.trim()) {
        return 0;
    }

    const GRID_TOP = 33;
    const ROW_HEIGHT = 42;
    const colWidth = 608;
    const maxY = 3120;
    const ctx = getScratchMeasureCtx();

    function snapToGrid(y) {
        if (y <= GRID_TOP) return GRID_TOP;
        const rows = Math.ceil((y - GRID_TOP) / ROW_HEIGHT);
        return GRID_TOP + (rows * ROW_HEIGHT);
    }

    let pageCount = 0;
    let colIndex = 0;
    let currentY = GRID_TOP;

    function advanceToNextColumn() {
        colIndex++;
        currentY = GRID_TOP;
        if (colIndex >= 3) {
            pageCount++;
            colIndex = 0;
        }
    }

    function wrapText(textToWrap, fontSize, fontName, bold) {
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arial, sans-serif`;
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
        } else if (pText.startsWith('### ')) {
            blocks.push({ type: 'h3', content: pText.substring(4).trim(), raw: pText });
        } else if (pText.startsWith('## ')) {
            blocks.push({ type: 'h2', content: pText.substring(3).trim(), raw: pText });
        } else if (pText.startsWith('# ')) {
            blocks.push({ type: 'h1', content: pText.substring(2).trim(), raw: pText });
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
        } else if (cleanLine.startsWith('# ') || cleanLine.startsWith('## ') || cleanLine.startsWith('### ') || cleanLine.startsWith('* ') || cleanLine.startsWith('- ') || cleanLine.startsWith('{{') || cleanLine.startsWith('[[')) {
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
            if (currentY > GRID_TOP) {
                advanceToNextColumn();
            }
            continue;
        }

        if (block.type === 'image') {
            const drawHeight = 400;
            const minMarginBottom = 14;
            const rowsNeeded = Math.ceil((drawHeight + minMarginBottom) / ROW_HEIGHT);
            const totalImageBlockHeight = rowsNeeded * ROW_HEIGHT;

            if (currentY + totalImageBlockHeight > maxY) {
                advanceToNextColumn();
            }
            currentY += totalImageBlockHeight;
        } else if (block.type === 'template_block' && block.templateNum === 1) {
            const imgHeight = 400;
            const fontSize = 24;
            const fontName = 'Arimo';
            const linesToDraw = wrapText(block.content, fontSize, fontName, false);
            const textLeadingStep = fontSize * 1.4;
            const totalTextHeight = linesToDraw.length * textLeadingStep + 12;

            if (block.targetRow !== null && block.targetRow !== undefined) {
                let targetYBottom = GRID_TOP + block.targetRow * ROW_HEIGHT;
                let targetYTop = targetYBottom - imgHeight;
                if (currentY > targetYTop || targetYBottom + totalTextHeight > maxY) {
                    advanceToNextColumn();
                    targetYBottom = GRID_TOP + block.targetRow * ROW_HEIGHT;
                    targetYTop = targetYBottom - imgHeight;
                }
                currentY = snapToGrid(targetYTop + imgHeight + 16 + (linesToDraw.length * textLeadingStep) + 14);
            } else {
                const compositeBlockHeight = imgHeight + totalTextHeight + 20;
                const rowsNeeded = Math.ceil((compositeBlockHeight + 14) / ROW_HEIGHT);
                const totalBlockHeight = rowsNeeded * ROW_HEIGHT;
                if (currentY + totalBlockHeight > maxY) {
                    advanceToNextColumn();
                }
                currentY += totalBlockHeight;
            }
        } else {
            let fontSize, fontName, bold = false;
            let step = ROW_HEIGHT;
            if (block.type === 'h1') {
                fontSize = 42; fontName = 'Anton'; bold = false; step = 56;
            } else if (block.type === 'h2') {
                fontSize = 36; fontName = 'Anton'; bold = false; step = 48;
            } else if (block.type === 'h3') {
                fontSize = 28; fontName = 'Anton'; bold = false; step = ROW_HEIGHT;
            } else {
                fontSize = 28; fontName = 'Arimo'; bold = false; step = ROW_HEIGHT;
            }

            const isBullet = block.type === 'bullet';
            const textToWrap = isBullet ? "    " + block.content : block.content;
            const linesToDraw = wrapText(textToWrap, fontSize, fontName, bold);

            for (let i = 0; i < linesToDraw.length; i++) {
                if (currentY + fontSize > maxY) {
                    advanceToNextColumn();
                }
                currentY += step;
            }
            currentY = snapToGrid(currentY + 14);
        }
    }

    if (currentY > GRID_TOP || colIndex > 0) {
        pageCount++;
    }

    return pageCount;
};
window.measurePublisherPages = window.measurePublisherPages;
globalThis.measurePublisherPages = window.measurePublisherPages;

window.renderPublisherPages = async (text) => {
    const pagesResults = [];
    const GRID_TOP = 33;
    const ROW_HEIGHT = 42;
    const columnsX = [33, 696, 1359];
    const colWidth = 608;
    const maxY = 3120;

    function snapToGrid(y) {
        if (y <= GRID_TOP) return GRID_TOP;
        const rows = Math.ceil((y - GRID_TOP) / ROW_HEIGHT);
        return GRID_TOP + (rows * ROW_HEIGHT);
    }

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
    let colIndex = 0;
    let currentY = GRID_TOP;
    let currentPageTextParts = [];

    function wrapText(textToWrap, fontSize, fontName, bold) {
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arial, sans-serif`;
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
            if (!url || typeof url !== 'string' || !url.trim()) {
                resolve(null);
                return;
            }
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
        currentY = GRID_TOP;
        currentPageTextParts = [];
    }

    function advanceToNextColumn() {
        colIndex++;
        currentY = GRID_TOP;
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
        } else if (pText.startsWith('### ')) {
            blocks.push({ type: 'h3', content: pText.substring(4).trim(), raw: pText });
        } else if (pText.startsWith('## ')) {
            blocks.push({ type: 'h2', content: pText.substring(3).trim(), raw: pText });
        } else if (pText.startsWith('# ')) {
            blocks.push({ type: 'h1', content: pText.substring(2).trim(), raw: pText });
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
        } else if (cleanLine.startsWith('# ') || cleanLine.startsWith('## ') || cleanLine.startsWith('### ') || cleanLine.startsWith('* ') || cleanLine.startsWith('- ') || cleanLine.startsWith('{{') || cleanLine.startsWith('[[')) {
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
            if (currentY > GRID_TOP) {
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
            // Enforce baseline grid alignment for images: calculate integer row span
            const minMarginBottom = 14;
            const rowsNeeded = Math.ceil((drawHeight + minMarginBottom) / ROW_HEIGHT);
            const totalImageBlockHeight = rowsNeeded * ROW_HEIGHT;

            if (currentY + totalImageBlockHeight > maxY) {
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
                ctx.font = 'bold 24px "Arimo", Arial, sans-serif';
                ctx.fillStyle = '#9ca3af';
                ctx.textAlign = 'center';
                ctx.fillText('Image Asset Placeholder', columnsX[colIndex] + colWidth / 2, currentY + drawHeight / 2);
                ctx.textAlign = 'left';
            }
            currentY += totalImageBlockHeight;
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
            const fontName = 'Arimo';
            const linesToDraw = wrapText(block.content, fontSize, fontName, false);
            const textLeadingStep = fontSize * 1.4;
            const totalTextHeight = linesToDraw.length * textLeadingStep + 12;

            if (block.targetRow !== null && block.targetRow !== undefined) {
                let targetYBottom = GRID_TOP + block.targetRow * ROW_HEIGHT;
                let targetYTop = targetYBottom - imgHeight;
                if (currentY > targetYTop || targetYBottom + totalTextHeight > maxY) {
                    advanceToNextColumn();
                    targetYBottom = GRID_TOP + block.targetRow * ROW_HEIGHT;
                    targetYTop = targetYBottom - imgHeight;
                }
                if (img) {
                    ctx.drawImage(img, columnsX[colIndex], targetYTop, colWidth, imgHeight);
                } else {
                    ctx.fillStyle = '#f3f4f6';
                    ctx.fillRect(columnsX[colIndex], targetYTop, colWidth, imgHeight);
                }
                currentY = targetYTop + imgHeight + 16;
                ctx.font = `${fontSize}px "${fontName}", Arial, sans-serif`;
                ctx.fillStyle = '#1a1a1a';
                for (let line of linesToDraw) {
                    ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                    currentY += textLeadingStep;
                }
                currentY = snapToGrid(currentY + 14);
            } else {
                const compositeBlockHeight = imgHeight + totalTextHeight + 20;
                const rowsNeeded = Math.ceil((compositeBlockHeight + 14) / ROW_HEIGHT);
                const totalBlockHeight = rowsNeeded * ROW_HEIGHT;
                if (currentY + totalBlockHeight > maxY) {
                    advanceToNextColumn();
                }
                if (img) {
                    ctx.drawImage(img, columnsX[colIndex], currentY, colWidth, imgHeight);
                } else {
                    ctx.fillStyle = '#f3f4f6';
                    ctx.fillRect(columnsX[colIndex], currentY, colWidth, imgHeight);
                }
                let captionY = currentY + imgHeight + 16;
                ctx.font = `${fontSize}px "${fontName}", Arial, sans-serif`;
                ctx.fillStyle = '#1a1a1a';
                for (let line of linesToDraw) {
                    ctx.fillText(line, columnsX[colIndex], captionY + fontSize);
                    captionY += textLeadingStep;
                }
                currentY += totalBlockHeight;
            }
            currentPageTextParts.push(`{{TEMPLATE_1: ${targetUrl} | ${block.content}}}`);
        } else {
            let fontSize, fontName, bold = false;
            let step = ROW_HEIGHT; // Default line advance sits strictly on the 42px baseline grid
            if (block.type === 'h1') {
                fontSize = 42; fontName = 'Anton'; bold = false; step = 56;
            } else if (block.type === 'h2') {
                fontSize = 36; fontName = 'Anton'; bold = false; step = 48;
            } else if (block.type === 'h3') {
                fontSize = 28; fontName = 'Anton'; bold = false; step = ROW_HEIGHT;
            } else {
                fontSize = 28; fontName = 'Arimo'; bold = false; step = ROW_HEIGHT;
            }
            const isBullet = block.type === 'bullet';
            const textToWrap = isBullet ? "    " + block.content : block.content;
            const linesToDraw = wrapText(textToWrap, fontSize, fontName, bold);
            ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arial, sans-serif`;
            ctx.fillStyle = '#1a1a1a';
            let currentParagraphRenderedLines = [];
            for (let i = 0; i < linesToDraw.length; i++) {
                const line = linesToDraw[i];
                if (currentY + fontSize > maxY) {
                    if (currentParagraphRenderedLines.length > 0) {
                        currentPageTextParts.push(currentParagraphRenderedLines.join(' '));
                        currentParagraphRenderedLines = [];
                    }
                    advanceToNextColumn();
                    ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arial, sans-serif`;
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
            // Snap currentY to the baseline grid with a 14px minimum separation gap
            currentY = snapToGrid(currentY + 14);
            if (currentParagraphRenderedLines.length > 0) {
                if (block.type === 'h1') currentPageTextParts.push('# ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'h2') currentPageTextParts.push('## ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'h3') currentPageTextParts.push('### ' + currentParagraphRenderedLines.join(' '));
                else if (block.type === 'bullet') currentPageTextParts.push('* ' + currentParagraphRenderedLines.join(' '));
                else currentPageTextParts.push(currentParagraphRenderedLines.join(' '));
            }
        }
    }
    if (currentY > GRID_TOP || colIndex > 0) {
        finalizeCurrentPage();
    }
    return JSON.stringify(pagesResults);
};
window.renderPublisherPages = window.renderPublisherPages;
globalThis.renderPublisherPages = window.renderPublisherPages;
''';
  web.document.head?.append(script);
}

@JS('measurePublisherPages')
external JSNumber? _measurePublisherPages(JSString text);

/// Fast zero-pixel layout measurement returning the exact page count on the baseline grid
/// without allocating canvas plates, requesting image assets, or encoding Base64 strings.
Future<int> measurePublisherPages(String text) async {
  try {
    _ensureRenderPublisherPagesScript();
    final jsRes = _measurePublisherPages(text.toJS);
    if (jsRes != null) {
      return jsRes.toDartInt;
    }
  } catch (e) {
    print('[measurePublisherPages Error] $e');
  }
  return 0;
}

@JS('renderPublisherPages')
external JSPromise? _renderPublisherPages(JSString text);

Future<String> renderPublisherPages(String text) async {
  try {
    _ensureRenderPublisherPagesScript();
    final promise = _renderPublisherPages(text.toJS);
    if (promise != null) {
      final jsRes = await promise.toDart;
      if (jsRes != null) {
        return (jsRes as JSString).toDart;
      }
    }
  } catch (e) {
    print('[renderPublisherPages Call] $e. Falling back to singular renderPublisherPage.');
  }
  try {
    final single = await renderPublisherPage(text);
    return '[$single]';
  } catch (e) {
    print('[renderPublisherPages Fallback Error] $e');
    return '[]';
  }
}

@JS('renderPublisherPage')
external JSPromise? _renderPublisherPage(JSString text);

Future<String> renderPublisherPage(String text) async {
  try {
    _ensureRenderPublisherPagesScript();
    final promise = _renderPublisherPage(text.toJS);
    if (promise != null) {
      final jsRes = await promise.toDart;
      if (jsRes != null) {
        return (jsRes as JSString).toDart;
      }
    }
  } catch (e) {
    print('[renderPublisherPage Error] $e');
    rethrow;
  }
  return '{}';
}

@JS('getCurrentUserId')
external JSString? _getCurrentUserId();
String? getCurrentUserId() => _getCurrentUserId()?.toDart;

@JS('getCurrentUserEmail')
external JSString? _getCurrentUserEmail();
String? getCurrentUserEmail() => _getCurrentUserEmail()?.toDart;

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
    JSString email,
    JSString password,
    JSString username,
    );
Future<void> registerWithFirebase(
    String email,
    String password,
    String username,
    ) async {
  await _registerWithFirebase(email.toJS, password.toJS, username.toJS).toDart;
}

@JS('logoutFromFirebase')
external JSPromise _logoutFromFirebase();
Future<void> logoutFromFirebase() async {
  await _logoutFromFirebase().toDart;
}

@JS('fnCall')
external JSPromise? _fnCall(JSString name, JSString dataStr);

Future<String> fnCall(String name, String dataStr) async {
  try {
    final promise = _fnCall(name.toJS, dataStr.toJS);
    if (promise != null) {
      final jsRes = await promise.toDart;
      if (jsRes != null) {
        return (jsRes as JSString).toDart;
      }
    }
  } catch (e) {
    print('[fnCall Error on "$name"] $e');
    rethrow;
  }
  return '{}';
}

@JS('fsGetDoc')
external JSPromise _fsGetDoc(JSString path);
Future<String> fsGetDoc(String path) async {
  final jsRes = await _fsGetDoc(path.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsListenDoc')
external JSFunction _fsListenDoc(JSString path, JSFunction callback);
FirebaseSubscription fsListenDoc(String path, void Function(String) callback) {
  final jsFunc = _fsListenDoc(
    path.toJS,
    ((JSString str) => callback(str.toDart)).toJS,
  );
  return WebSubscription(jsFunc);
}

@JS('fsListenQuery')
external JSFunction _fsListenQuery(
    JSString path,
    JSString? field,
    JSString? op,
    JSString? valueJson,
    JSString? orderBy,
    JSBoolean? desc,
    JSFunction callback,
    );
FirebaseSubscription fsListenQuery(
    String path,
    String? field,
    String? op,
    String? valueJson,
    String? orderBy,
    bool? desc,
    void Function(String) callback,
    ) {
  final jsFunc = _fsListenQuery(
    path.toJS,
    field?.toJS,
    op?.toJS,
    valueJson?.toJS,
    orderBy?.toJS,
    desc?.toJS,
    ((JSString str) => callback(str.toDart)).toJS,
  );
  return WebSubscription(jsFunc);
}

@JS('fsQuery')
external JSPromise _fsQuery(
    JSString path,
    JSString field,
    JSString op,
    JSString valueJson,
    JSString orderBy,
    );
Future<String> fsQuery(
    String path,
    String field,
    String op,
    String valueJson,
    String orderBy,
    ) async {
  final jsRes = await _fsQuery(
    path.toJS,
    field.toJS,
    op.toJS,
    valueJson.toJS,
    orderBy.toJS,
  ).toDart;
  return (jsRes as JSString).toDart;
}

@JS('fsUpdateDoc')
external JSPromise _fsUpdateDoc(JSString path, JSString dataStr);
Future<void> fsUpdateDoc(String path, String dataStr) async {
  await _fsUpdateDoc(path.toJS, dataStr.toJS).toDart;
}

@JS('fsSetDoc')
external JSPromise _fsSetDoc(
    JSString path,
    JSString dataStr,
    JSBoolean merge,
    );
Future<void> fsSetDoc(String path, String dataStr, bool merge) async {
  await _fsSetDoc(path.toJS, dataStr.toJS, merge.toJS).toDart;
}

@JS('fsDeleteDoc')
external JSPromise _fsDeleteDoc(JSString path);
Future<void> fsDeleteDoc(String path) async {
  await _fsDeleteDoc(path.toJS).toDart;
}

@JS('fsAddDoc')
external JSPromise _fsAddDoc(JSString path, JSString dataStr);
Future<String> fsAddDoc(String path, String dataStr) async {
  final jsRes = await _fsAddDoc(path.toJS, dataStr.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('stUpload')
external JSPromise _stUpload(
    JSString path,
    JSUint8Array bytes,
    JSString contentType,
    );
Future<String> stUpload(
    String path,
    List<int> bytes,
    String contentType,
    ) async {
  final Uint8List uint8List =
  bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final jsArray = uint8List.toJS;
  final jsRes = await _stUpload(path.toJS, jsArray, contentType.toJS).toDart;
  return (jsRes as JSString).toDart;
}

@JS('pickAndReadFile')
external void _pickAndReadFile(JSString inputId, JSFunction callback);
void pickAndReadFile(
    String inputId,
    void Function(String base64, String fileName, String objectUrl) callback,
    ) {
  _pickAndReadFile(
    inputId.toJS,
    ((JSString base64, JSString fileName, JSString objectUrl) {
      callback(base64.toDart, fileName.toDart, objectUrl.toDart);
    }).toJS,
  );
}

@JS('readInputFile')
external void _readInputFile(JSString inputId, JSFunction callback);
void readInputFile(
    String inputId,
    void Function(String base64, String fileName, String objectUrl) callback,
    ) {
  _readInputFile(
    inputId.toJS,
    ((JSString base64, JSString fileName, JSString objectUrl) {
      callback(base64.toDart, fileName.toDart, objectUrl.toDart);
    }).toJS,
  );
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
external JSPromise? _geocodeAddress(JSString address);
Future<String?> geocodeAddress(String address) async {
  final cleanAddress = address.trim();
  if (cleanAddress.isEmpty) return null;

  // 1. Primary: Route through server-side verified Cloud Function with Firestore caching
  try {
    final res = await fnCall('geocode_address', jsonEncode({'address': cleanAddress}));
    if (res.isNotEmpty && res != 'null') {
      final decoded = jsonDecode(res);
      if (decoded is Map && decoded['status'] == 'success') {
        return res;
      }
    }
  } catch (e) {
    print('[geocodeAddress Server Callable] $e. Falling back to client-side geocoding.');
  }

  // 2. Fallback: Query local JS window.geocodeAddress if Cloud Function is offline
  try {
    final jsRes = await _geocodeAddress(cleanAddress.toJS)?.toDart;
    if (jsRes == null) return null;
    return (jsRes as JSString).toDart;
  } catch (e) {
    print('[geocodeAddress Error] $e');
    return null;
  }
}

@JS('renderEntityMap')
external void _renderEntityMap(JSString containerId, JSString markersJson);
void renderEntityMap(String containerId, String markersJson) {
  try {
    _renderEntityMap(containerId.toJS, markersJson.toJS);
  } catch (e) {
    print('[renderEntityMap Error] $e');
  }
}

class WebFieldValue {
  static Map<String, dynamic> serverTimestamp() => {'__op': 'serverTimestamp'};
  static Map<String, dynamic> increment(num val) => {
    '__op': 'increment',
    'value': val,
  };
  static Map<String, dynamic> arrayUnion(List<dynamic> elements) => {
    '__op': 'arrayUnion',
    'values': elements,
  };
  static Map<String, dynamic> arrayRemove(List<dynamic> elements) => {
    '__op': 'arrayRemove',
    'values': elements,
  };
  static Map<String, dynamic> delete() => {'__op': 'delete'};
}