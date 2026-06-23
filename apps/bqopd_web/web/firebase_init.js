const firebaseConfig = {
  apiKey: "AIzaSyAKrrl8l8A-3RDzaI04qgp99-vpeMLMR_g",
  authDomain: "bqopd-9ce06.firebaseapp.com",
  projectId: "bqopd-9ce06",
  storageBucket: "bqopd-9ce06.appspot.com",
  messagingSenderId: "17060476719",
  appId: "1:17060476719:web:9c7e201c50938561e2d3da"
};
firebase.initializeApp(firebaseConfig);

const db = firebase.firestore();
const storage = firebase.storage();
const functions = firebase.functions();

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
    return db.doc(path).onSnapshot(
        function(d) { dartCallback(JSON.stringify({id: d.id, path: d.ref.path, exists: d.exists, data: d.exists ? serializeFirebaseData(d.data()) : null})); },
        function(err) { console.error("fsListenDoc error on path " + path + ":", err); }
    );
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
    return q.onSnapshot(
        function(s) {
            let docs = s.docs.map(function(d) { return {id: d.id, path: d.ref.path, exists: d.exists, data: serializeFirebaseData(d.data())}; });
            dartCallback(JSON.stringify(docs));
        },
        function(err) { console.error("fsListenQuery error on path " + path + ":", err); }
    );
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

// --- HIGH-PERFORMANCE OFFSCREEN CANVAS COMPILER ---
// Generates three WebP sizes on click: original, list, and grid.
window.renderPublisherPage = async (text) => {
    const canvas = document.createElement('canvas');
    canvas.width = 2000;
    canvas.height = 3200;
    const ctx = canvas.getContext('2d');

    // Fill with pure white background
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, 2000, 3200);

    // Draw outer black border (11px)
    ctx.lineWidth = 11;
    ctx.strokeStyle = '#000000';
    ctx.strokeRect(5.5, 5.5, 2000 - 11, 3200 - 11);

    // Draw vertical dividers (Starts 99px from top, ends 99px from bottom)
    ctx.fillStyle = '#000000';
    ctx.fillRect(663, 99, 11, 3200 - 198);
    ctx.fillRect(1326, 99, 11, 3200 - 198);

    const columnsX = [33, 696, 1359];
    const colWidth = 608;
    const maxY = 3150;

    let colIndex = 0;
    let currentY = 33;

    // Text wrapping utility (declared inside render block to safely capture ctx & colWidth)
    function wrapText(text, fontSize, fontName, bold) {
        ctx.font = `${bold ? 'bold ' : ''}${fontSize}px ${fontName}`;
        const words = text.split(' ');
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

    // Image loading utility with CORS guard (declared inside render block)
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

    // Parse markdown text blocks
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
            // Decouple contents to check if a row specifies a specific start index line
            let targetRow = null;
            let captionText = tMatch[3].trim();
            const rowMatch = /^row=(\d+)\s*\|\s*(.*)$/i.exec(captionText);
            if (rowMatch) {
                targetRow = parseInt(rowMatch[1]);
                captionText = rowMatch[2].trim();
            }

            // Always enforce a column break before and after the template block
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
            blocks.push({ type: 'h3', content: pText.substring(3).trim() });
        } else if (pText.startsWith('##')) {
            blocks.push({ type: 'h2', content: pText.substring(2).trim() });
        } else if (pText.startsWith('#')) {
            blocks.push({ type: 'h1', content: pText.substring(1).trim() });
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
        } else if (cleanLine.startsWith('#') || cleanLine.startsWith('*') || cleanLine.startsWith('-') || cleanLine.startsWith('{{') || cleanLine.startsWith('[[')) {
            commitParagraph();
            currentParagraph = cleanLine;
            commitParagraph();
        } else {
            currentParagraph = currentParagraph ? currentParagraph + " " + cleanLine : cleanLine;
        }
    }
    commitParagraph();

    // Render blocks onto canvas
    for (let block of blocks) {
        if (colIndex >= 3) break;

        if (block.type === 'column_break') {
            // Advance to the top of the next column if we've written anything in this one
            if (currentY > 33) {
                colIndex++;
                currentY = 33;
            }
            continue;
        }

        if (block.type === 'image') {
            const targetUrl = block.url;
            let img = null;
            if (targetUrl && targetUrl.trim().length > 0) {
                img = await loadImage(targetUrl);
            }

            const drawHeight = 400; // Standardized local placeholder height

            if (currentY + drawHeight > maxY) {
                colIndex++;
                currentY = 33;
            }

            if (colIndex < 3) {
                if (img) {
                    const drawRatioHeight = colWidth * (img.height / img.width);
                    ctx.drawImage(img, columnsX[colIndex], currentY, colWidth, drawRatioHeight);
                    currentY += drawRatioHeight + 20;
                } else {
                    // Draw a beautiful local vector wireframe placeholder to prevent CORS canvas tainting entirely!
                    ctx.fillStyle = '#f3f4f6';
                    ctx.fillRect(columnsX[colIndex], currentY, colWidth, drawHeight);

                    ctx.lineWidth = 4;
                    ctx.strokeStyle = '#d1d5db';
                    ctx.strokeRect(columnsX[colIndex] + 10, currentY + 10, colWidth - 20, drawHeight - 20);

                    // Draw soft elegant wireframe diagonal lines
                    ctx.lineWidth = 2;
                    ctx.beginPath();
                    ctx.moveTo(columnsX[colIndex] + 10, currentY + 10);
                    ctx.lineTo(columnsX[colIndex] + colWidth - 10, currentY + drawHeight - 10);
                    ctx.moveTo(columnsX[colIndex] + colWidth - 10, currentY + 10);
                    ctx.lineTo(columnsX[colIndex] + 10, currentY + drawHeight - 10);
                    ctx.stroke();

                    // Text inside placeholder
                    ctx.font = 'bold 24px Arial';
                    ctx.fillStyle = '#9ca3af';
                    ctx.textAlign = 'center';
                    ctx.fillText('Image Asset Placeholder', columnsX[colIndex] + colWidth / 2, currentY + drawHeight / 2);

                    // Reset alignment back to default
                    ctx.textAlign = 'left';

                    currentY += drawHeight + 20;
                }
            }
        } else if (block.type === 'template_block' && block.templateNum === 1) {
            const targetUrl = block.url;
            let img = null;
            if (targetUrl && targetUrl.trim().length > 0) {
                img = await loadImage(targetUrl);
            }

            // Estimate metrics dynamically to handle column split bounds safely
            let imgHeight = 400; // Standard fallback height
            if (img) {
                imgHeight = colWidth * (img.height / img.width);
            }

            const fontSize = 24; // Subtle elegant paragraph font sizing
            const fontName = 'Arial';
            const linesToDraw = wrapText(block.content, fontSize, fontName, false);
            const textLeadingStep = fontSize * 1.4;
            const totalTextHeight = linesToDraw.length * textLeadingStep + 12;

            if (block.targetRow !== null && block.targetRow !== undefined) {
                // Bottom of the image sits at targetRow * 42 pixels down from top
                let targetYBottom = 33 + block.targetRow * 42;
                let targetYTop = targetYBottom - imgHeight;

                // Check for column overflow or overlapping existing content
                if (currentY > targetYTop || targetYBottom + totalTextHeight > maxY) {
                    colIndex++;
                    currentY = 33;
                    // Recalculate based on next column's top
                    targetYBottom = 33 + block.targetRow * 42;
                    targetYTop = targetYBottom - imgHeight;
                }

                if (colIndex < 3) {
                    // Draw image at targetYTop (sitting on targetYBottom)
                    if (img) {
                        ctx.drawImage(img, columnsX[colIndex], targetYTop, colWidth, imgHeight);
                    } else {
                        ctx.fillStyle = '#f3f4f6';
                        ctx.fillRect(columnsX[colIndex], targetYTop, colWidth, imgHeight);
                    }
                    currentY = targetYTop + imgHeight + 16; // Update currentY to point to the bottom of the image + spacing!

                    // Print text payload sequences neatly underneath
                    ctx.font = `${fontSize}px ${fontName}`;
                    ctx.fillStyle = '#1a1a1a';
                    for (let line of linesToDraw) {
                        ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                        currentY += textLeadingStep;
                    }
                    currentY += 24; // Extra paragraph padding block spacing
                }
            } else {
                // Handle multi-column overflow protection (standard layout fallback)
                const compositeBlockHeight = imgHeight + totalTextHeight + 20;
                if (currentY + compositeBlockHeight > maxY) {
                    colIndex++;
                    currentY = 33;
                }

                if (colIndex < 3) {
                    // Draw the image container box edge-to-edge
                    if (img) {
                        ctx.drawImage(img, columnsX[colIndex], currentY, colWidth, imgHeight);
                    } else {
                        ctx.fillStyle = '#f3f4f6';
                        ctx.fillRect(columnsX[colIndex], currentY, colWidth, imgHeight);
                    }
                    currentY += imgHeight + 16; // Spacing block directly under image bounds

                    // Print text payload sequences neatly underneath
                    ctx.font = `${fontSize}px ${fontName}`;
                    ctx.fillStyle = '#1a1a1a';
                    for (let line of linesToDraw) {
                        ctx.fillText(line, columnsX[colIndex], currentY + fontSize);
                        currentY += textLeadingStep;
                    }
                    currentY += 24; // Extra paragraph padding block spacing
                }
            }
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

            for (let line of linesToDraw) {
                if (currentY + fontSize > maxY) {
                    colIndex++;
                    currentY = 33;
                }

                if (colIndex >= 3) break;

                // Justify body paragraphs
                const isLastLine = line === linesToDraw[linesToDraw.length - 1];
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
            }
            currentY += spaceBelow;
        }
    }

    // Expose scaled canvas exporters
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

    return JSON.stringify({
        original: originalBase64,
        list: listBase64,
        grid: gridBase64
    });
};