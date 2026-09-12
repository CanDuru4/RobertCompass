/**
 * Exercise the no-cost Firebase protocol with real Firestore security rules.
 * Every gameplay write uses a client SDK; admin access only seeds organizer data.
 * @module spark-tests
 * @example FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test test/spark.test.js
 */
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, query, where, writeBatch,
  runTransaction, serverTimestamp, Timestamp, GeoPoint } from 'firebase/firestore';

let env;
const projectId = 'demo-compass-spark-tests';
const gameId = 'course';
const end = Date.now() + 86400000;
let counter = 0;
const stamp = serverTimestamp;
const sessionRef = (db, id) => doc(db, 'sessions', id);
const boardRef = (db, id) => doc(db, 'games', gameId, 'leaderboard', id);
const profileRef = client => doc(client.db, 'users', client.uid);
const attemptRef = (client, id, point) => doc(client.db, 'users', client.uid, 'attempts', `${id}_${point}`);

before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  env = await initializeTestEnvironment({ projectId, firestore: { host: '127.0.0.1', port: 8080,
    rules: await readFile(new URL('../../firestore.spark.rules', import.meta.url), 'utf8') } });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'games', gameId), { published: true, name: 'Course', startsAt: Date.now() - 3600000,
      endsAt: end, durationSeconds: 3600, maxTeamSize: 2, requiresEntryCode: false,
      routes: [{ checkpointIds: ['one', 'two'] }, { checkpointIds: ['two', 'one'] }] });
    await setDoc(doc(db, 'privateGames', gameId), { entryCodeHash: null, answers: { one: ['north'], two: ['4'] } });
    for (const id of ['one', 'two']) await setDoc(doc(db, 'games', gameId, 'checkpoints', id), {
      latitude: 41, longitude: 29, radiusMeters: 50, points: 100,
    });
  });
});
after(async () => { await env?.cleanup(); });

async function player(verified = true) {
  const uid = `player-${++counter}`;
  const db = env.authenticatedContext(uid, { email_verified: verified, auth_time: Math.floor(Date.now() / 1000) }).firestore();
  const client = { uid, db };
  if (verified) await setDoc(profileRef(client), { displayName: uid, activeSessionId: null, deleting: false, updatedAt: stamp() });
  return client;
}

function board(s) {
  const start = s.startedAt?.toMillis?.();
  const last = s.lastScoredAt?.toMillis?.();
  const limit = Math.min((start ?? s.createdAt.toMillis()) + (start === undefined ? 3600000 : s.durationSeconds * 1000), s.gameEndsAt);
  const elapsedSeconds = s.status === 'expired' && start !== undefined ? Math.floor((limit - start) / 1000)
    : start === undefined || last === undefined ? 0 : Math.floor((last - start) / 1000);
  return { teamName: s.teamName, score: s.score, status: s.status, elapsedSeconds, updatedAt: stamp() };
}

async function create(client, overrides = {}) {
  const ref = doc(collection(client.db, 'sessions'));
  const code = (++counter).toString(16).toUpperCase().padStart(12, '0');
  const data = { schemaVersion: 2, gameId, gameName: 'Course', teamName: `Team ${counter}`, ownerId: client.uid,
    memberIds: [client.uid], memberNames: { [client.uid]: client.uid }, joinCode: code,
    createdAt: stamp(), startedAt: null, finishedAt: null, updatedAt: stamp(), lastScoredAt: null,
    lastCheckpointId: null, status: 'waiting', score: 0, checkpointIds: [], completedIds: [],
    durationSeconds: 3600, gameEndsAt: end, routeIndex: null, ...overrides };
  const batch = writeBatch(client.db);
  batch.set(ref, data);
  batch.set(doc(client.db, 'joinCodes', code), { sessionId: ref.id });
  batch.update(profileRef(client), { activeSessionId: ref.id, updatedAt: stamp() });
  await batch.commit();
  return ref.id;
}

async function join(client, id) {
  try { await runTransaction(client.db, async tx => {
    const ref = sessionRef(client.db, id);
    const s = (await tx.get(ref)).data();
    if (s.memberIds.includes(client.uid)) return;
    tx.update(ref, { memberIds: [...s.memberIds, client.uid], memberNames: { ...s.memberNames, [client.uid]: client.uid }, updatedAt: stamp() });
    tx.update(profileRef(client), { activeSessionId: id, updatedAt: stamp() });
  }); } catch (error) {
    const current = (await getDoc(sessionRef(client.db, id))).data();
    if (!current.memberIds.includes(client.uid)) throw error;
  }
}

async function start(client, id) {
  await runTransaction(client.db, async tx => {
    const ref = sessionRef(client.db, id);
    const s = (await tx.get(ref)).data();
    const index = Math.floor(s.createdAt.nanoseconds / 1000) % 2;
    const next = { ...s, startedAt: stamp(), status: 'active', routeIndex: index,
      checkpointIds: index === 0 ? ['one', 'two'] : ['two', 'one'], updatedAt: stamp() };
    tx.set(ref, next);
    tx.set(boardRef(client.db, id), board(next));
  });
}

async function receipt(client, id, point, overrides = {}) {
  await setDoc(attemptRef(client, id, point), { sessionId: id, checkpointId: point,
    answer: point === 'one' ? 'north' : '4', location: new GeoPoint(41, 29), accuracy: 5,
    capturedAt: Date.now(), receivedAt: stamp(), ...overrides });
}

async function award(client, id, point, overrides = {}) {
  for (let retry = 0; retry < 3; retry++) {
    try { return await runTransaction(client.db, async tx => {
    const ref = sessionRef(client.db, id);
    const s = (await tx.get(ref)).data();
    if (s.completedIds.includes(point)) return 'duplicate';
    const a = (await tx.get(attemptRef(client, id, point))).data();
    const completedIds = [...s.completedIds, point];
    const complete = completedIds.length === s.checkpointIds.length;
    const scoredAt = s.lastScoredAt && s.lastScoredAt.toMillis() > a.receivedAt.toMillis() ? s.lastScoredAt : a.receivedAt;
    const next = { ...s, score: s.score + 100, completedIds, lastScoredAt: scoredAt, lastCheckpointId: point,
      status: complete ? 'completed' : 'active', finishedAt: complete ? scoredAt : null, updatedAt: stamp(), ...overrides };
    tx.set(ref, next);
    tx.set(boardRef(client.db, id), board(next));
    return 'accepted';
  }); } catch (error) {
    const current = (await getDoc(sessionRef(client.db, id))).data();
    if (current.completedIds.includes(point)) return 'duplicate';
    if (retry === 2 || current.status !== 'active' || Object.keys(overrides).length) throw error;
    }
  }
}

test('verified players create a lobby and invite with an atomic profile pointer', async () => {
  const client = await player();
  const id = await create(client);
  assert.equal((await getDoc(profileRef(client))).data().activeSessionId, id);
  assert.equal((await getDoc(sessionRef(client.db, id))).data().createdAt instanceof Timestamp, true);
  await assertFails(create(client));
  await assertFails(updateDoc(profileRef(client), { activeSessionId: null, updatedAt: stamp() }));
});

test('unverified and anonymous access, listing invites, and reading answers are denied', async () => {
  const client = await player(false);
  await assertFails(setDoc(profileRef(client), { displayName: 'No', activeSessionId: null, deleting: false, updatedAt: stamp() }));
  const valid = await player();
  await assertFails(getDoc(doc(valid.db, 'privateGames', gameId)));
  await assertFails(getDocs(collection(valid.db, 'joinCodes')));
  await assertFails(getDocs(collection(valid.db, 'sessions')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'games', gameId)));
});

test('concurrent joins preserve capacity and membership; only captain starts', async () => {
  const captain = await player();
  const mate = await player();
  const outsider = await player();
  const id = await create(captain);
  await Promise.all([join(mate, id), join(mate, id)]);
  await assertFails(join(outsider, id));
  await assertFails(start(mate, id));
  await start(captain, id);
  await assertFails(getDoc(sessionRef(outsider.db, id)));
  await assertFails(updateDoc(sessionRef(captain.db, id), { startedAt: Timestamp.fromMillis(0), updatedAt: stamp() }));
});

test('wrong answers, stale fixes, distant locations, and forged acceptance timestamps fail', async () => {
  const client = await player();
  const id = await create(client);
  await start(client, id);
  await assertFails(receipt(client, id, 'one', { answer: 'south' }));
  await assertFails(receipt(client, id, 'one', { capturedAt: Date.now() - 60000 }));
  await assertFails(receipt(client, id, 'one', { location: new GeoPoint(40, 29) }));
  await assertFails(receipt(client, id, 'one', { accuracy: 60 }));
  await assertFails(receipt(client, id, 'one', { receivedAt: Timestamp.fromMillis(0) }));
});

test('scores and the leaderboard change atomically and retries award points once', async () => {
  const captain = await player();
  const mate = await player();
  const id = await create(captain);
  await join(mate, id);
  await start(captain, id);
  await Promise.all([receipt(captain, id, 'one'), receipt(mate, id, 'one')]);
  await assertFails(award(captain, id, 'one', { score: 999 }));
  const results = await Promise.all([award(captain, id, 'one'), award(mate, id, 'one')]);
  assert.equal(results.filter(result => result === 'accepted').length, 1);
  await assertFails(updateDoc(sessionRef(captain.db, id), { score: 999, updatedAt: stamp() }));
  await assertFails(updateDoc(boardRef(captain.db, id), { score: 999, updatedAt: stamp() }));
  await receipt(mate, id, 'two');
  await award(mate, id, 'two');
  const s = (await getDoc(sessionRef(captain.db, id))).data();
  assert.equal(s.status, 'completed');
  assert.equal(s.score, 200);
  assert.equal((await getDoc(boardRef(captain.db, id))).data().score, 200);
  await assertSucceeds(deleteDoc(attemptRef(mate, id, 'two')));
  await assertFails(deleteDoc(doc(captain.db, 'users', mate.uid, 'attempts', `${id}_two`)));
});

test('members can leave a lobby and captains can cancel with a consistent board', async () => {
  const captain = await player();
  const mate = await player();
  const id = await create(captain);
  await join(mate, id);
  const leave = writeBatch(mate.db);
  leave.update(sessionRef(mate.db, id), { memberIds: [captain.uid], memberNames: { [captain.uid]: captain.uid }, updatedAt: stamp() });
  leave.update(profileRef(mate), { activeSessionId: null, updatedAt: stamp() });
  await leave.commit();
  await start(captain, id);
  const s = (await getDoc(sessionRef(captain.db, id))).data();
  const next = { ...s, status: 'cancelled', finishedAt: stamp(), updatedAt: stamp() };
  const cancel = writeBatch(captain.db);
  cancel.set(sessionRef(captain.db, id), next);
  cancel.set(boardRef(captain.db, id), board(next));
  await cancel.commit();
  await create(captain);
});

test('deletion locks gameplay and removes only the requesting identity from history', async () => {
  const client = await player();
  const id = await create(client);
  await updateDoc(sessionRef(client.db, id), { status: 'cancelled', finishedAt: stamp(), updatedAt: stamp() });
  await updateDoc(profileRef(client), { deleting: true, displayName: 'Deleted player', activeSessionId: null, updatedAt: stamp() });
  await assertFails(create(client));
  await assertFails(updateDoc(profileRef(client), { deleting: false, updatedAt: stamp() }));
  await updateDoc(sessionRef(client.db, id), { memberIds: [], memberNames: {}, ownerId: '', teamName: 'Deleted team', updatedAt: stamp() });
  assert.equal((await getDocs(query(collection(client.db, 'sessions'), where('memberIds', 'array-contains', client.uid)))).empty, true);
});

test('different checkpoints accept concurrent and out-of-order receipts without losing points', async () => {
  for (const concurrent of [false, true]) {
    const captain = await player();
    const mate = await player();
    const id = await create(captain);
    await join(mate, id);
    await start(captain, id);
    await receipt(captain, id, 'one');
    await receipt(mate, id, 'two');
    const last = (await getDoc(attemptRef(mate, id, 'two'))).data().receivedAt;
    if (concurrent) await Promise.all([award(mate, id, 'two'), award(captain, id, 'one')]);
    else { await award(mate, id, 'two'); await award(captain, id, 'one'); }
    const s = (await getDoc(sessionRef(captain.db, id))).data();
    assert.equal(s.score, 200);
    assert.equal(s.status, 'completed');
    assert.deepEqual(new Set(s.completedIds), new Set(['one', 'two']));
    assert.equal(s.finishedAt.isEqual(last), true);
  }
});

test('entry proofs require the organizer code and cannot bypass course or deadline fields', async () => {
  const client = await player();
  const locked = 'locked';
  const hash = createHash('sha256').update('Organizer-test-code').digest('hex');
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    const course = (await getDoc(doc(db, 'games', gameId))).data();
    await setDoc(doc(db, 'games', locked), { ...course, requiresEntryCode: true });
    await setDoc(doc(db, 'privateGames', locked), { entryCodeHash: hash, answers: {} });
  });
  await assertFails(create(client, { gameId: locked }));
  await assertFails(setDoc(doc(client.db, 'users', client.uid, 'entries', locked), { hash: 'wrong', updatedAt: stamp() }));
  await setDoc(doc(client.db, 'users', client.uid, 'entries', locked), { hash, updatedAt: stamp() });
  await assertFails(create(client, { gameId: locked, durationSeconds: 99999 }));
  await assertFails(create(client, { gameId: locked, gameEndsAt: end + 1 }));
  await create(client, { gameId: locked });
});

test('expired activities reject new receipts and finalize only with the exact deadline', async () => {
  const client = await player();
  const id = await create(client);
  await start(client, id);
  await assertFails(updateDoc(sessionRef(client.db, id), { status: 'expired', finishedAt: stamp(), updatedAt: stamp() }));
  const startedAt = Timestamp.fromMillis(Date.now() - 3700000);
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(sessionRef(context.firestore(), id), { createdAt: Timestamp.fromMillis(Date.now() - 3800000), startedAt });
  });
  await assertFails(receipt(client, id, 'one'));
  const s = (await getDoc(sessionRef(client.db, id))).data();
  const next = { ...s, status: 'expired', finishedAt: Timestamp.fromMillis(startedAt.toMillis() + 3600000), updatedAt: stamp() };
  const batch = writeBatch(client.db);
  batch.set(sessionRef(client.db, id), next);
  batch.set(boardRef(client.db, id), board(next));
  await batch.commit();
  assert.equal((await getDoc(boardRef(client.db, id))).data().elapsedSeconds, 3600);
  await create(client);
});

test('membership, course records, receipts, and board times cannot be forged', async () => {
  const captain = await player();
  const mate = await player();
  const id = await create(captain);
  await assertFails(updateDoc(sessionRef(mate.db, id), { memberIds: [captain.uid, mate.uid],
    memberNames: { [captain.uid]: 'Impersonated captain', [mate.uid]: mate.uid }, updatedAt: stamp() }));
  await assertFails(updateDoc(doc(captain.db, 'games', gameId), { durationSeconds: 999999 }));
  await assertFails(updateDoc(doc(captain.db, 'privateGames', gameId), { answers: {} }));
  await join(mate, id);
  await start(captain, id);
  await assertFails(receipt(captain, id, 'one', { capturedAt: Date.now() + 60000 }));
  await assertFails(receipt(captain, id, 'one', { accuracy: -1 }));
  await assertFails(getDocs(collection(mate.db, 'users', captain.uid, 'attempts')));
  await receipt(captain, id, 'one');
  await award(captain, id, 'one');
  await assertFails(updateDoc(boardRef(captain.db, id), { elapsedSeconds: 0, updatedAt: stamp() }));
  await assertFails(updateDoc(sessionRef(mate.db, id), { status: 'cancelled', finishedAt: stamp(), updatedAt: stamp() }));
  await assertFails(updateDoc(profileRef(captain), { deleting: true, displayName: 'Deleted player', activeSessionId: null, updatedAt: stamp() }));
});

test('removing a completed captain preserves the teammate, transfers ownership, and retains scores', async () => {
  const captain = await player();
  const mate = await player();
  const id = await create(captain);
  await join(mate, id);
  await start(captain, id);
  for (const point of ['one', 'two']) { await receipt(captain, id, point); await award(captain, id, point); }
  await updateDoc(profileRef(captain), { deleting: true, displayName: 'Deleted player', activeSessionId: null, updatedAt: stamp() });
  const s = (await getDoc(sessionRef(captain.db, id))).data();
  const next = { ...s, memberIds: [mate.uid], memberNames: { [mate.uid]: mate.uid }, ownerId: mate.uid, updatedAt: stamp() };
  const batch = writeBatch(captain.db);
  batch.set(sessionRef(captain.db, id), next);
  batch.set(boardRef(captain.db, id), board(next));
  await batch.commit();
  const result = (await getDoc(sessionRef(mate.db, id))).data();
  assert.equal(result.ownerId, mate.uid);
  assert.equal(result.score, 200);
  assert.deepEqual(result.memberNames, { [mate.uid]: mate.uid });
  await assertFails(getDoc(sessionRef(captain.db, id)));
  await assertFails(receipt(captain, id, 'one'));
});
