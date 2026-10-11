if (typeof window.firebaseConfig === 'undefined') {
  window.firebaseConfig = {
    apiKey: "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g",
    authDomain: "bqopd-9ce06.firebaseapp.com",
    projectId: "bqopd-9ce06",
    storageBucket: "bqopd-9ce06.appspot.com",
    messagingSenderId: "17060476719",
    appId: "1:17060476719:web:9c7e201c50938561e2d3da"
  };
}

if (!firebase.apps.length) {
  firebase.initializeApp(window.firebaseConfig);
}
var db = firebase.firestore();
var storage = firebase.storage();
var functions = firebase.functions();

window.loginWithFirebase = function(email, password) {
    return firebase.auth().signInWithEmailAndPassword(email, password);
};

window.registerWithFirebase = function(email, password, username) {
    return firebase.auth().createUserWithEmailAndPassword(email, password).then(function(userCredential) {
        var user = userCredential.user;
        var batch = db.batch();
        batch.set(db.collection('Users').doc(user.uid), {
            uid: user.uid, email: user.email, username: username,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            Editor: false, bio: '', firstName: '', lastName: ''
        });
        batch.set(db.collection('usernames').doc(username.toLowerCase()), {
            uid: user.uid, email: user.email, updatedAt: firebase.firestore.FieldValue.serverTimestamp()
        });
        return batch.commit();
    });
};

window.logoutFromFirebase = function() { return firebase.auth().signOut(); };
window.getCurrentUserId = function() { return firebase.auth().currentUser ? firebase.auth().currentUser.uid : null; };
window.getCurrentUserEmail = function() { return firebase.auth().currentUser ? firebase.auth().currentUser.email : null; };

window.onAuthStateChangedListener = function(callback) {
    firebase.auth().onAuthStateChanged(function(user) {
        callback(user ? user.uid : null, user ? user.email : null);
    });
};

function serializeFirebaseData(data) {
    if (data === null) return data;
    if (data === undefined) return data;
    if (data.toDate) {
        if (typeof data.toDate === 'function') {
            return { __type: 'timestamp', iso: data.toDate().toISOString() };
        }
    }
    if (Array.isArray(data)) return data.map(serializeFirebaseData);
    if (typeof data === 'object') {
        let res = {};
        for (let key in data) res[key] = serializeFirebaseData(data[key]);
        return res;
    }
    return data;
}

function parseFirebaseOps(obj) {
    if (obj === null) return obj;
    if (typeof obj !== 'object') return obj;
    if (Array.isArray(obj)) return obj.map(parseFirebaseOps);
    if (obj.__op === 'serverTimestamp') return firebase.firestore.FieldValue.serverTimestamp();
    if (obj.__op === 'increment') return firebase.firestore.FieldValue.increment(obj.value);
    if (obj.__op === 'arrayUnion') return firebase.firestore.FieldValue.arrayUnion.apply(null, obj.values);
    if (obj.__op === 'arrayRemove') return firebase.firestore.FieldValue.arrayRemove.apply(null, obj.values);
    if (obj.__op === 'delete') return firebase.firestore.FieldValue.delete();
    let res = {};
    for (let key in obj) res[key] = parseFirebaseOps(obj[key]);
    return res;
}

window.fsGetDoc = function(path) {
    return db.doc(path).get()
        .then(function(d) { return JSON.stringify({id: d.id, path: d.ref.path, exists: d.exists, data: d.exists ? serializeFirebaseData(d.data()) : null}); })
        .catch(function(err) { return JSON.stringify({id: '', path: path, exists: false, error: err.message}); });
};

window.fsListenDoc = function(path, dartCallback) {
    var unsub = db.doc(path).onSnapshot(
        function(d) { dartCallback(JSON.stringify({id: d.id, path: d.ref.path, exists: d.exists, data: d.exists ? serializeFirebaseData(d.data()) : null})); },
        function(err) { console.error("fsListenDoc error on path " + path + ":", err); }
    );
    unsub.callAsFunction = unsub;
    return unsub;
};

window.fsListenQuery = function(path, field, op, valueJson, orderBy, desc, dartCallback) {
    let q = db.collection(path);
    if (field) {
        if (op) {
            if (valueJson) {
                q = q.where(field, op, JSON.parse(valueJson));
            }
        }
    }
    if (orderBy) {
        let dir = 'asc';
        if (desc) dir = 'desc';
        q = q.orderBy(orderBy, dir);
    }
    var unsub = q.onSnapshot(
        function(s) {
            let docs = s.docs.map(function(d) { return {id: d.id, path: d.ref.path, exists: d.exists, data: serializeFirebaseData(d.data())}; });
            dartCallback(JSON.stringify(docs));
        },
        function(err) { console.error("fsListenQuery error on path " + path + ":", err); }
    );
    unsub.callAsFunction = unsub;
    return unsub;
};

window.fsUpdateDoc = function(path, dataStr) { return db.doc(path).update(parseFirebaseOps(JSON.parse(dataStr))).catch(function(err) { console.error("fsUpdateDoc error:", err); throw err; }); };
window.fsSetDoc = function(path, dataStr, merge) { return db.doc(path).set(parseFirebaseOps(JSON.parse(dataStr)), {merge: merge}).catch(function(err) { console.error("fsSetDoc error:", err); throw err; }); };
window.fsDeleteDoc = function(path) { return db.doc(path).delete().catch(function(err) { console.error("fsDeleteDoc error:", err); throw err; }); };
window.fsAddDoc = function(path, dataStr) { return db.collection(path).add(parseFirebaseOps(JSON.parse(dataStr))).then(function(r) { return r.id; }).catch(function(err) { console.error("fsAddDoc error:", err); throw err; }); };

window.fsQuery = function(path, field, op, valueJson, orderBy) {
    let q = db.collection(path);
    if (field) {
        if (op) {
            if (valueJson) {
                q = q.where(field, op, JSON.parse(valueJson));
            }
        }
    }
    if (orderBy) q = q.orderBy(orderBy);
    return q.get()
        .then(function(s) { return JSON.stringify(s.docs.map(function(d) { return {id: d.id, path: d.ref.path, exists: d.exists, data: serializeFirebaseData(d.data())}; })); })
        .catch(function(err) { console.error("fsQuery error:", err); return JSON.stringify([]); });
};

window.fnCall = function(name, dataStr) { return functions.httpsCallable(name)(JSON.parse(dataStr)).then(function(r) { return JSON.stringify(r.data); }).catch(function(err) { console.error("fnCall error:", err); throw err; }); };
window.stUpload = function(path, bytes, contentType) { return storage.ref(path).put(bytes, {contentType: contentType}).then(function(s) { return s.ref.getDownloadURL(); }).catch(function(err) { console.error("stUpload error:", err); throw err; }); };

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
            if (!url || typeof url !== 'string' || !url.trim()) {
                resolve(null);
                return;
            }
            const img = new Image();
            let timer = null;
            let settled = false;

            function finish(result) {
                if (settled) return;
                settled = true;
                if (timer) clearTimeout(timer);
                resolve(result);
            }

            timer = setTimeout(() => {
                console.warn('[loadImage Timeout] Bypassing stalled image:', url);
                finish(null);
            }, 3500);

            if (url.startsWith('http://') || url.startsWith('https://')) {
                img.crossOrigin = "anonymous";
            }
            img.onload = () => finish(img);
            img.onerror = (err) => {
                console.warn('[loadImage Error] Could not load:', url, err);
                finish(null);
            };
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
            const textToWrap = isBullet ? "   " + block.content : block.content;
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

// Guarantee globalThis and window exposure for Dart web interop
globalThis.renderPublisherPages = window.renderPublisherPages;

window.renderPublisherPage = async (text) => {
    const multiJson = await window.renderPublisherPages(text);
    const pages = JSON.parse(multiJson);
    if (pages && pages.length > 0) {
        return JSON.stringify(pages[0]);
    }
    return JSON.stringify({ original: '', list: '', grid: '' });
};

globalThis.renderPublisherPage = window.renderPublisherPage;

// ---------------------------------------------------------------------------
// 2000x3200 Full-Page Google Map Cover using Official Google Maps Static API
// ---------------------------------------------------------------------------
window.renderMapCoverPage = async (configJson) => {
    console.log('[renderMapCoverPage] Starting Google Maps Static cover generation...');
    const config = typeof configJson === 'string' ? JSON.parse(configJson) : configJson;
    const center = config.center || { lat: 39.8283, lng: -98.5795, address: "United States" };
    const letters = Array.isArray(config.letters) ? config.letters : [];
    const folioTitle = config.title || `Letters near ${center.address}`;
    const apiKey = (window.firebaseConfig && window.firebaseConfig.apiKey) || "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g";

    const canvas = document.createElement('canvas');
    canvas.width = 2000;
    canvas.height = 3200;
    const ctx = canvas.getContext('2d');

    // Default neutral roadmap background
    ctx.fillStyle = '#e5e3df';
    ctx.fillRect(0, 0, 2000, 3200);

    // 1. Gather all points
    const points = [];
    if (center.lat != null && center.lng != null) {
        points.push({ lat: center.lat, lng: center.lng, isCenter: true });
    }
    letters.forEach(l => {
        if (l.lat != null && l.lng != null) {
            points.push({ lat: l.lat, lng: l.lng, isCenter: false });
        }
    });

    if (points.length === 0) {
        points.push({ lat: 43.8396, lng: -91.2436, isCenter: true });
    }

    // 2. Obtain official Google Maps Static image
    let mapDataUrl = null;

    // Primary route: fetch via Cloud Function (returns data:image/png;base64,... which never taints canvas)
    try {
        console.log('[renderMapCoverPage] Calling Cloud Function fetch_static_map with points:', points.length);
        const fnResult = await functions.httpsCallable('fetch_static_map')({
            markers: points,
            width: 400,
            height: 640,
            scale: 2,
            api_key: apiKey
        });
        if (fnResult && fnResult.data && fnResult.data.status === 'success' && fnResult.data.data_url) {
            mapDataUrl = fnResult.data.data_url;
            console.log('[renderMapCoverPage] Successfully obtained map data URL from Cloud Function.');
        } else {
            console.warn('[renderMapCoverPage] Cloud Function returned non-success:', fnResult && fnResult.data);
        }
    } catch (fnErr) {
        console.warn('[renderMapCoverPage] Cloud Function fetch_static_map threw:', fnErr);
    }

    // Fallback route: direct Google Static Maps URL
    if (!mapDataUrl) {
        console.log('[renderMapCoverPage] Using direct Static Map URL fallback.');
        const queryParts = [
            'size=400x640',
            'scale=2',
            'maptype=roadmap',
            `key=${apiKey}`
        ];
        points.forEach(p => {
            const color = p.isCenter ? '0xd32f2f' : '0xea4335';
            const size = p.isCenter ? 'mid' : 'small';
            queryParts.append ? queryParts.push(`markers=color:${color}%7Csize:${size}%7C${p.lat},${p.lng}`) : null;
        });
        mapDataUrl = `https://maps.googleapis.com/maps/api/staticmap?${queryParts.join('&')}`;
    }

    // 3. Draw the official Google Map image across the full 2000x3200 canvas
    await new Promise((resolve) => {
        const img = new Image();
        img.crossOrigin = "anonymous";
        img.onload = () => {
            console.log('[renderMapCoverPage] Static map image loaded into image element. Drawing to canvas...');
            ctx.drawImage(img, 0, 0, 2000, 3200);
            resolve();
        };
        img.onerror = (e) => {
            console.warn('[renderMapCoverPage] Static map image failed to render:', e);
            resolve();
        };
        img.src = mapDataUrl;
    });

    // 4. Overlay authentic Google Maps UI chrome
    // Zoom Controls (+ / -) in bottom-right
    ctx.save();
    const zoomBox = { x: 1840, y: 2920, width: 84, height: 168, r: 10 };
    ctx.shadowColor = 'rgba(0, 0, 0, 0.18)';
    ctx.shadowBlur = 18;
    ctx.shadowOffsetY = 4;

    ctx.beginPath();
    ctx.roundRect(zoomBox.x, zoomBox.y, zoomBox.width, zoomBox.height, zoomBox.r);
    ctx.fillStyle = '#ffffff';
    ctx.fill();
    ctx.restore();

    ctx.strokeStyle = '#dadce0';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(zoomBox.x + 12, zoomBox.y + 84);
    ctx.lineTo(zoomBox.x + zoomBox.width - 12, zoomBox.y + 84);
    ctx.stroke();

    // "+" symbol
    ctx.strokeStyle = '#5f6368';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(zoomBox.x + 42, zoomBox.y + 26);
    ctx.lineTo(zoomBox.x + 42, zoomBox.y + 58);
    ctx.moveTo(zoomBox.x + 26, zoomBox.y + 42);
    ctx.lineTo(zoomBox.x + 58, zoomBox.y + 42);
    ctx.stroke();

    // "−" symbol
    ctx.beginPath();
    ctx.moveTo(zoomBox.x + 26, zoomBox.y + 126);
    ctx.lineTo(zoomBox.x + 58, zoomBox.y + 126);
    ctx.stroke();

    // Google Logo in bottom-left
    ctx.textAlign = 'left';
    ctx.font = 'bold 36px Product Sans, Arial, sans-serif';
    const gX = 80;
    const gY = 3120;
    const gLetters = [
        { char: 'G', color: '#4285F4' },
        { char: 'o', color: '#EA4335' },
        { char: 'p', color: '#FBBC05' },
        { char: 'g', color: '#4285F4' },
        { char: 'l', color: '#34A853' },
        { char: 'e', color: '#EA4335' },
    ];
    let curGX = gX;
    gLetters.forEach(item => {
        ctx.fillStyle = item.color;
        ctx.fillText(item.char, curGX, gY);
        curGX += ctx.measureText(item.char).width;
    });

    // 5. Export high-res WebP images (original, list, and grid)
    function getScaledBase64(targetWidth, targetHeight) {
        const scaled = document.createElement('canvas');
        scaled.width = targetWidth;
        scaled.height = targetHeight;
        const sCtx = scaled.getContext('2d');
        sCtx.drawImage(canvas, 0, 0, 2000, 3200, 0, 0, targetWidth, targetHeight);
        return scaled.toDataURL('image/webp', 0.8).split(',')[1];
    }

    const originalBase64 = canvas.toDataURL('image/webp', 0.9).split(',')[1];
    const listBase64 = getScaledBase64(800, 1280);
    const gridBase64 = getScaledBase64(450, 720);

    console.log('[renderMapCoverPage] Successfully finalized 2000x3200 Google Map cover.');
    return JSON.stringify({
        original: originalBase64,
        list: listBase64,
        grid: gridBase64,
        text: `Map Cover: ${folioTitle}\nCenter: ${center.address}\nLetters: ${letters.length}`
    });
};

globalThis.renderMapCoverPage = window.renderMapCoverPage;

window.getPlacePredictions = (input) => {
    return new Promise((resolve) => {
        if (typeof google === 'undefined' || !google.maps || !google.maps.places) {
            resolve(JSON.stringify([]));
            return;
        }
        const service = new google.maps.places.AutocompleteService();
        service.getPlacePredictions({ input: input }, (predictions, status) => {
            if (status !== google.maps.places.PlacesServiceStatus.OK || !predictions) {
                resolve(JSON.stringify([]));
                return;
            }
            const results = predictions.map(p => ({
                description: p.description,
                placeId: p.place_id
            }));
            resolve(JSON.stringify(results));
        });
    });
};

window.initAddressAutocomplete = (inputId, callback) => {
    const input = document.getElementById(inputId);
    if (!input) return;

    if (typeof google === 'undefined' || !google.maps || !google.maps.places) {
        setTimeout(() => window.initAddressAutocomplete(inputId, callback), 150);
        return;
    }

    const autocomplete = new google.maps.places.Autocomplete(input, {
        fields: ['formatted_address']
    });

    autocomplete.addListener('place_changed', () => {
        const place = autocomplete.getPlace();
        if (place && place.formatted_address) {
            callback(place.formatted_address);
        }
    });
};

window.geocodeAddress = async (address) => {
    if (!address || typeof address !== 'string' || !address.trim()) {
        return null;
    }
    const cleanAddress = address.trim();

    if (typeof google !== 'undefined' && google.maps && google.maps.Geocoder) {
        try {
            const googleResult = await new Promise((resolve) => {
                const geocoder = new google.maps.Geocoder();
                geocoder.geocode({ address: cleanAddress }, (results, status) => {
                    if (status === 'OK' && results && results.length > 0) {
                        const loc = results[0].geometry.location;
                        resolve(JSON.stringify({ lat: loc.lat(), lng: loc.lng() }));
                    } else {
                        console.warn('[geocodeAddress] Google Geocoder status:', status, 'for address:', cleanAddress);
                        resolve(null);
                    }
                });
            });
            if (googleResult) return googleResult;
        } catch (e) {
            console.warn('[geocodeAddress] Google Geocoder threw:', e);
        }
    }

    try {
        console.log('[geocodeAddress] Attempting OpenStreetMap Nominatim fallback for:', cleanAddress);
        const encoded = encodeURIComponent(cleanAddress);
        const resp = await fetch(`https://nominatim.openstreetmap.org/search?q=${encoded}&format=json&limit=1`, {
            headers: { 'Accept': 'application/json' }
        });
        if (resp.ok) {
            const data = await resp.json();
            if (Array.isArray(data) && data.length > 0) {
                const lat = parseFloat(data[0].lat);
                const lng = parseFloat(data[0].lon);
                console.log('[geocodeAddress] Nominatim resolved:', cleanAddress, '->', lat, lng);
                return JSON.stringify({ lat: lat, lng: lng });
            }
        }
    } catch (err) {
        console.error('[geocodeAddress] Nominatim fallback failed:', err);
    }
    return null;
};

window.renderEntityMap = (containerId, markersJson) => {
    if (typeof google === 'undefined' || !google.maps) return;
    const container = document.getElementById(containerId);
    if (!container) return;

    let markersData = [];
    try {
        markersData = JSON.parse(markersJson);
    } catch (e) {
        console.error('[renderEntityMap] Error parsing JSON:', e);
        return;
    }

    const map = new google.maps.Map(container, {
        zoom: 3,
        center: { lat: 39.8283, lng: -98.5795 },
        disableDefaultUI: true,
        zoomControl: true,
    });

    if (!markersData || markersData.length === 0) return;

    const bounds = new google.maps.LatLngBounds();
    markersData.forEach((m) => {
        const pos = { lat: m.lat, lng: m.lng };
        const marker = new google.maps.Marker({
            position: pos,
            map: map,
            title: m.title,
        });

        const infoWindow = new google.maps.InfoWindow({
            content: `<div style="padding:4px; font-family: sans-serif; font-size: 13px;"><b>${m.title}</b>${m.subtitle ? `<br/><small>${m.subtitle}</small>` : ''}</div>`
        });

        marker.addListener('click', () => {
            infoWindow.open(map, marker);
        });

        bounds.extend(pos);
    });

    map.fitBounds(bounds);
    if (markersData.length === 1) {
        map.setZoom(12);
    }
};