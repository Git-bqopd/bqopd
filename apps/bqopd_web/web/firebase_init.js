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