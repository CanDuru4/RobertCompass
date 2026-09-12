/**
 * Verify the deployed Spark protocol using two temporary Firebase Auth accounts.
 * Owner access creates and cleans exact test fixtures; gameplay uses client rules.
 * No verification email is sent and no existing account or course is modified.
 * @module live-smoke
 * @example node scripts/live-smoke.js --project robert-compass --apply
 */
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { initializeApp as adminApp } from 'firebase-admin/app';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, deleteUser } from 'firebase/auth';
import { getFirestore, doc, collection, getDoc, getDocs, setDoc, updateDoc, writeBatch,
  runTransaction, serverTimestamp, GeoPoint, onSnapshot, terminate } from 'firebase/firestore';
import { firebaseCLICredential, ownerFirestore } from './owner-credentials.js';

const { values } = parseArgs({ options: { project: { type: 'string' }, apply: { type: 'boolean' } } });
assert.equal(values.project, 'robert-compass', 'Only the explicitly configured project is supported.');
assert.equal(values.apply, true, 'Use --apply to authorize temporary live test fixtures.');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, undefined, 'Remove emulator settings.');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, undefined, 'Remove emulator settings.');
const projectId = values.project;
const config = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-',
  new URL('../../Radventure/Configuration/FirebaseConfig.plist', import.meta.url).pathname], { encoding: 'utf8' }));
assert.equal(config.PROJECT_ID, projectId);
const owner = adminApp({ projectId, credential: await firebaseCLICredential() });
const db = await ownerFirestore(projectId);
const accounts = [];
const refs = [];
const clients = [];
const suffix = randomBytes(8).toString('hex');
const gameId = `qa-${suffix}`;
const sessionId = `qa-session-${suffix}`;
const code = randomBytes(6).toString('hex').toUpperCase();
const end = Date.now() + 300000;
const stamp = serverTimestamp;
let listener;
let fixturesCreated = false;
let stage = 'fixture setup';

function tracked(path) {
  const ref = db.doc(path);
  refs.push(ref);
  return ref;
}

function board(s) {
  const last = s.lastScoredAt?.toMillis?.();
  const start = s.startedAt?.toMillis?.();
  return { teamName: s.teamName, score: s.score, status: s.status,
    elapsedSeconds: last === undefined || start === undefined ? 0 : Math.floor((Math.floor(last) - Math.floor(start)) / 1000), updatedAt: stamp() };
}

async function award(client) {
  for (let retry = 0; retry < 3; retry++) {
    try {
      return await runTransaction(client.db, async tx => {
        const ref = doc(client.db, 'sessions', sessionId);
        const s = (await tx.get(ref)).data();
        if (s.completedIds.includes('point')) return;
        const receipt = (await tx.get(doc(client.db, 'users', client.uid, 'attempts', `${sessionId}_point`))).data();
        const next = { ...s, score: 100, status: 'completed', completedIds: ['point'], lastCheckpointId: 'point',
          lastScoredAt: receipt.receivedAt, finishedAt: receipt.receivedAt, updatedAt: stamp() };
        tx.set(ref, next);
        tx.set(doc(client.db, 'games', gameId, 'leaderboard', sessionId), board(next));
      });
    } catch (error) { if (retry === 2) throw error; }
  }
}

try {
  const batch = db.batch();
  batch.create(tracked(`games/${gameId}`), { name: 'Deployment check (temporary)', rules: 'Automated check, not a playable route.',
    published: true, startsAt: Date.now() - 1000, endsAt: end, durationSeconds: 60, maxTeamSize: 2,
    latitude: 41, longitude: 29, requiresEntryCode: false, routes: [{ checkpointIds: ['point'] }] });
  batch.create(tracked(`games/${gameId}/checkpoints/point`), { name: 'Test checkpoint', question: 'Test input', options: [],
    latitude: 41, longitude: 29, radiusMeters: 50, points: 100 });
  batch.create(tracked(`privateGames/${gameId}`), { answers: { point: ['correct'] }, entryCodeHash: null });
  await batch.commit();
  fixturesCreated = true;
  tracked(`sessions/${sessionId}`);
  tracked(`joinCodes/${code}`);
  tracked(`games/${gameId}/leaderboard/${sessionId}`);
  for (let index = 0; index < 2; index++) {
    const password = randomBytes(32).toString('base64url');
    const email = `compass-qa-${suffix}-${index}@example.test`;
    const account = await adminAuth(owner).createUser({ email, password, emailVerified: true, displayName: `QA player ${index}` });
    accounts.push(account.uid);
    const app = initializeApp({ projectId, apiKey: config.API_KEY, appId: config.GOOGLE_APP_ID }, `qa-${index}-${suffix}`);
    const auth = getAuth(app);
    await signInWithEmailAndPassword(auth, email, password);
    const client = { app, auth, db: getFirestore(app), uid: account.uid };
    clients.push(client);
    tracked(`users/${account.uid}`);
    tracked(`users/${account.uid}/attempts/${sessionId}_point`);
    await setDoc(doc(client.db, 'users', account.uid), { displayName: account.uid, activeSessionId: null, deleting: false, updatedAt: stamp() });
  }
  const [captain, mate] = clients;
  stage = 'team creation and joining';
  const create = writeBatch(captain.db);
  create.set(doc(captain.db, 'sessions', sessionId), { schemaVersion: 2, gameId, gameName: 'Deployment check (temporary)', teamName: 'QA team',
    ownerId: captain.uid, memberIds: [captain.uid], memberNames: { [captain.uid]: captain.uid }, joinCode: code,
    createdAt: stamp(), updatedAt: stamp(), startedAt: null, finishedAt: null, lastScoredAt: null, lastCheckpointId: null,
    status: 'waiting', score: 0, checkpointIds: [], completedIds: [], durationSeconds: 60, gameEndsAt: end, routeIndex: null });
  create.set(doc(captain.db, 'joinCodes', code), { sessionId });
  create.update(doc(captain.db, 'users', captain.uid), { activeSessionId: sessionId, updatedAt: stamp() });
  await create.commit();
  assert.equal((await getDoc(doc(mate.db, 'joinCodes', code))).data().sessionId, sessionId);
  const join = writeBatch(mate.db);
  join.update(doc(mate.db, 'sessions', sessionId), { memberIds: accounts, memberNames: Object.fromEntries(accounts.map(uid => [uid, uid])), updatedAt: stamp() });
  join.update(doc(mate.db, 'users', mate.uid), { activeSessionId: sessionId, updatedAt: stamp() });
  await join.commit();
  stage = 'captain start and live leaderboard';
  await runTransaction(captain.db, async tx => {
    const ref = doc(captain.db, 'sessions', sessionId);
    const s = (await tx.get(ref)).data();
    const next = { ...s, status: 'active', startedAt: stamp(), checkpointIds: ['point'], routeIndex: 0, updatedAt: stamp() };
    tx.set(ref, next);
    tx.set(doc(captain.db, 'games', gameId, 'leaderboard', sessionId), board(next));
  });
  const observed = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Leaderboard listener timed out.')), 20000);
    listener = onSnapshot(doc(mate.db, 'games', gameId, 'leaderboard', sessionId), snapshot => {
      if (snapshot.data()?.score === 100) { clearTimeout(timer); resolve(); }
    }, error => { clearTimeout(timer); reject(error); });
  });
  observed.catch(() => {});
  stage = 'answer checks and simultaneous scoring';
  await assert.rejects(getDoc(doc(captain.db, 'privateGames', gameId)), error => error.code === 'permission-denied');
  await assert.rejects(getDocs(collection(captain.db, 'joinCodes')), error => error.code === 'permission-denied');
  for (const client of clients) {
    const a = { sessionId, checkpointId: 'point', answer: 'correct', location: new GeoPoint(41, 29), accuracy: 5, capturedAt: Date.now(), receivedAt: stamp() };
    await assert.rejects(setDoc(doc(client.db, 'users', client.uid, 'attempts', `${sessionId}_point`), { ...a, answer: 'wrong' }), error => error.code === 'permission-denied');
    await setDoc(doc(client.db, 'users', client.uid, 'attempts', `${sessionId}_point`), a);
  }
  await Promise.all(clients.map(award));
  await observed;
  listener();
  listener = undefined;
  const session = (await getDoc(doc(captain.db, 'sessions', sessionId))).data();
  assert.equal(session.score, 100);
  assert.equal(session.status, 'completed');
  await assert.rejects(updateDoc(doc(captain.db, 'games', gameId, 'leaderboard', sessionId), { score: 999, updatedAt: stamp() }), error => error.code === 'permission-denied');
  stage = 'account cleanup';
  for (const client of clients) {
    await updateDoc(doc(client.db, 'users', client.uid), { displayName: 'Deleted player', activeSessionId: null, deleting: true, updatedAt: stamp() });
    await runTransaction(client.db, async tx => {
      const ref = doc(client.db, 'sessions', sessionId);
      const s = (await tx.get(ref)).data();
      const memberIds = s.memberIds.filter(uid => uid !== client.uid);
      const memberNames = { ...s.memberNames };
      delete memberNames[client.uid];
      const next = { ...s, memberIds, memberNames, ownerId: s.ownerId === client.uid ? memberIds[0] ?? '' : s.ownerId,
        teamName: memberIds.length ? s.teamName : 'Deleted team', updatedAt: stamp() };
      tx.set(ref, next);
      tx.set(doc(client.db, 'games', gameId, 'leaderboard', sessionId), board(next));
    });
    await deleteUser(client.auth.currentUser);
  }
  console.log('PASS: live email/password sign-in, two-player team, captain start, protected answers, concurrent scoring, leaderboard listener, and account deletion.');
} catch (error) {
  console.error(`FAIL at ${stage}: ${error.code ?? error.name ?? 'unknown'}`);
  process.exitCode = 1;
} finally {
  listener?.();
  for (const client of clients) { await terminate(client.db); await deleteApp(client.app); }
  for (const uid of accounts) {
    try { await adminAuth(owner).deleteUser(uid); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  }
  if (fixturesCreated) {
    const cleanup = db.batch();
    refs.forEach(ref => cleanup.delete(ref));
    await cleanup.commit();
  }
  await db.terminate();
  console.log('Temporary QA accounts and exact test documents cleaned up.');
}
