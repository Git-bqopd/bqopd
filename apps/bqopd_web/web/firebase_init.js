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
            uid: user.uid,
            email: user.email,
            username: username,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            Editor: false,
            bio: '',
            firstName: '',
            lastName: ''
        });
        batch.set(db.collection('usernames').doc(username.toLowerCase()), {
            uid: user.uid,
            email: user.email,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp()
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
    if (data === null || data === undefined) return data;
    if (data.toDate && typeof data.toDate === 'function') {
        return { __type: 'timestamp', iso: data.toDate().toISOString() };
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
    if (obj === null || typeof obj !== 'object') return obj;
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
        .then(function(d) {
            return JSON.stringify({
                id: d.id,
                path: d.ref.path,
                exists: d.exists,
                data: d.exists ? serializeFirebaseData(d.data()) : null
            });
        })
        .catch(function(err) {
            return JSON.stringify({id: '', path: path, exists: false, error: err.message});
        });
};

window.fsListenDoc = function(path, dartCallback) {
    var unsub = db.doc(path).onSnapshot(
        function(d) {
            dartCallback(JSON.stringify({
                id: d.id,
                path: d.ref.path,
                exists: d.exists,
                data: d.exists ? serializeFirebaseData(d.data()) : null
            }));
        },
        function(err) { console.error("fsListenDoc error on path " + path + ":", err); }
    );
    unsub.callAsFunction = unsub;
    return unsub;
};

window.fsListenQuery = function(path, field, op, valueJson, orderBy, desc, dartCallback) {
    let q = db.collection(path);
    if (field && op && valueJson) {
        q = q.where(field, op, JSON.parse(valueJson));
    }
    if (orderBy) {
        let dir = desc ? 'desc' : 'asc';
        q = q.orderBy(orderBy, dir);
    }
    var unsub = q.onSnapshot(
        function(s) {
            let docs = s.docs.map(function(d) {
                return {id: d.id, path: d.ref.path, exists: d.exists, data: serializeFirebaseData(d.data())};
            });
            dartCallback(JSON.stringify(docs));
        },
        function(err) { console.error("fsListenQuery error on path " + path + ":", err); }
    );
    unsub.callAsFunction = unsub;
    return unsub;
};

window.fsUpdateDoc = function(path, dataStr) {
    return db.doc(path).update(parseFirebaseOps(JSON.parse(dataStr))).catch(function(err) {
        console.error("fsUpdateDoc error:", err);
        throw err;
    });
};

window.fsSetDoc = function(path, dataStr, merge) {
    return db.doc(path).set(parseFirebaseOps(JSON.parse(dataStr)), {merge: merge}).catch(function(err) {
        console.error("fsSetDoc error:", err);
        throw err;
    });
};

window.fsDeleteDoc = function(path) {
    return db.doc(path).delete().catch(function(err) {
        console.error("fsDeleteDoc error:", err);
        throw err;
    });
};

window.fsAddDoc = function(path, dataStr) {
    return db.collection(path).add(parseFirebaseOps(JSON.parse(dataStr))).then(function(r) {
        return r.id;
    }).catch(function(err) {
        console.error("fsAddDoc error:", err);
        throw err;
    });
};

window.fsQuery = function(path, field, op, valueJson, orderBy) {
    let q = db.collection(path);
    if (field && op && valueJson) {
        q = q.where(field, op, JSON.parse(valueJson));
    }
    if (orderBy) q = q.orderBy(orderBy);
    return q.get()
        .then(function(s) {
            return JSON.stringify(s.docs.map(function(d) {
                return {id: d.id, path: d.ref.path, exists: d.exists, data: serializeFirebaseData(d.data())};
            }));
        })
        .catch(function(err) {
            console.error("fsQuery error:", err);
            return JSON.stringify([]);
        });
};

// Configured with a 5-minute (300,000ms) client timeout to prevent deadline-exceeded failures during heavy folio compilation
window.fnCall = function(name, dataStr) {
    return functions.httpsCallable(name, { timeout: 300000 })(JSON.parse(dataStr)).then(function(r) {
        return JSON.stringify(r.data);
    }).catch(function(err) {
        console.error("fnCall error on " + name + ":", err);
        throw err;
    });
};

window.stUpload = function(path, bytes, contentType) {
    return storage.ref(path).put(bytes, {contentType: contentType}).then(function(s) {
        return s.ref.getDownloadURL();
    }).catch(function(err) {
        console.error("stUpload error:", err);
        throw err;
    });
};

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
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arimo, sans-serif`;
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
            blocks.push({ type: 'h3', content: pText.substring(4).trim() });
        } else if (pText.startsWith('## ')) {
            blocks.push({ type: 'h2', content: pText.substring(3).trim() });
        } else if (pText.startsWith('# ')) {
            blocks.push({ type: 'h1', content: pText.substring(2).trim() });
        } else if (pText.startsWith('* ') || pText.startsWith('- ')) {
            blocks.push({ type: 'bullet', content: pText.substring(2).trim() });
        } else {
            blocks.push({ type: 'text', content: pText });
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
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arimo, sans-serif`;
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
                ctx.font = 'bold 24px "Arimo", sans-serif';
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
                ctx.font = `${fontSize}px "${fontName}", Arimo, sans-serif`;
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
                ctx.font = `${fontSize}px "${fontName}", Arimo, sans-serif`;
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
            ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arimo, sans-serif`;
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
                    ctx.font = `${bold ? 'bold ' : ''}${fontSize}px "${fontName}", Arimo, sans-serif`;
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

window.renderMapCoverPage = async (configJson) => {
    console.log('[renderMapCoverPage] Generating clean Google Maps cover with standard pins...');
    const config = typeof configJson === 'string' ? JSON.parse(configJson) : configJson;
    const center = config.center || { lat: 43.8396, lng: -91.2436, address: "La Crosse, WI" };
    const letters = Array.isArray(config.letters) ? config.letters : [];
    const folioTitle = config.title || `Letters near ${center.address}`;
    const apiKey = (window.firebaseConfig && window.firebaseConfig.apiKey) || "";

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
        const fnPayload = {
            markers: allCoords.map(c => ({ lat: c.lat, lng: c.lng, isCenter: c.isCenter })),
            center: `${centerLat},${centerLng}`,
            zoom: zoom,
            width: 400,
            height: 640,
            scale: 2
        };
        if (apiKey) {
            fnPayload.api_key = apiKey;
        }
        const fnResult = await functions.httpsCallable('fetch_static_map', { timeout: 60000 })(fnPayload);
        if (fnResult && fnResult.data && fnResult.data.status === 'success' && fnResult.data.data_url) {
            await new Promise((resolve) => {
                const img = new Image();
                img.onload = () => {
                    ctx.drawImage(img, 0, 0, 2000, 3200);
                    mapLoaded = true;
                    resolve();
                };
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
                    tImg.onload = () => {
                        ctx.drawImage(tImg, destX, destY, tileSize, tileSize);
                        resolve();
                    };
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

    console.log('[renderMapCoverPage] Successfully finalized clean 2000x3200 map cover with pins.');
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
        // Support modern AutocompleteSuggestion if available
        if (google.maps.places.AutocompleteSuggestion && typeof google.maps.places.AutocompleteSuggestion.fetchAutocompleteSuggestions === 'function') {
            google.maps.places.AutocompleteSuggestion.fetchAutocompleteSuggestions({ input: input })
                .then(({ suggestions }) => {
                    const results = (suggestions || []).map(s => {
                        const pred = s.placePrediction;
                        return {
                            description: pred.text ? pred.text.toString() : (pred.displayName || ''),
                            placeId: pred.placeId || ''
                        };
                    });
                    resolve(JSON.stringify(results));
                })
                .catch(() => {
                    // Fallback to legacy service
                    _legacyGetPlacePredictions(input, resolve);
                });
            return;
        }
        _legacyGetPlacePredictions(input, resolve);
    });
};

function _legacyGetPlacePredictions(input, resolve) {
    if (typeof google === 'undefined' || !google.maps || !google.maps.places || !google.maps.places.AutocompleteService) {
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
}

window.initAddressAutocomplete = (inputId, callback) => {
    const input = document.getElementById(inputId);
    if (!input) return;
    if (typeof google === 'undefined' || !google.maps || !google.maps.places) {
        setTimeout(() => window.initAddressAutocomplete(inputId, callback), 150);
        return;
    }
    if (input._autocompleteBound) return;
    input._autocompleteBound = true;

    // Check for modern PlaceAutocompleteElement to eliminate deprecation warning
    if (typeof google.maps.places.PlaceAutocompleteElement !== 'undefined') {
        try {
            const pac = new google.maps.places.PlaceAutocompleteElement();
            pac.style.width = '100%';
            pac.style.boxSizing = 'border-box';

            const handleSelect = async (event) => {
                let address = '';
                if (event.placePrediction && typeof event.placePrediction.toPlace === 'function') {
                    const place = event.placePrediction.toPlace();
                    await place.fetchFields({ fields: ['formattedAddress', 'displayName'] });
                    address = place.formattedAddress || place.displayName || '';
                } else if (event.place) {
                    if (typeof event.place.fetchFields === 'function') {
                        await event.place.fetchFields({ fields: ['formattedAddress', 'displayName'] });
                        address = event.place.formattedAddress || event.place.displayName || '';
                    } else {
                        address = event.place.formatted_address || event.place.formattedAddress || '';
                    }
                }
                if (address) {
                    input.value = address;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    callback(address);
                }
            };

            pac.addEventListener('gmp-select', handleSelect);
            pac.addEventListener('gmp-placeselect', handleSelect);

            if (input.parentNode) {
                input.style.display = 'none';
                input.parentNode.insertBefore(pac, input.nextSibling);
                return;
            }
        } catch (e) {
            console.warn('[initAddressAutocomplete] PlaceAutocompleteElement fallback to Autocomplete:', e);
        }
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

    // 1. Primary: Server-side verified Cloud Function with Firestore geocache
    try {
        const result = await functions.httpsCallable('geocode_address', { timeout: 60000 })({ address: cleanAddress });
        if (result && result.data && result.data.status === 'success') {
            return JSON.stringify(result.data);
        }
    } catch (e) {
        console.warn('[geocodeAddress] Server callable geocode_address failed:', e);
    }

    // 2. Fallback: Google Maps Geocoder SDK in browser
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