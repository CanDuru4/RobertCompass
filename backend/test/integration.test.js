import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, collection, query, where, getDocs, updateDoc } from 'firebase/firestore';
import { createHandlers } from '../src/service.js';

const projectId = 'demo-robert-compass';
const now = Date.parse('2026-09-12T14:00:00Z');
let clock = now;
let app, db, env, service;
const request = (uid, data = {}, token = {}) => ({ auth: { uid, token: { email_verified: true, name: uid, ...token } }, data });
const fix = { latitude: 41, longitude: 29, accuracy: 5, capturedAt: now };

before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080', 'Tests require the loopback Firestore emulator.');
  app = initializeApp({ projectId });
  db = getFirestore(app);
  service = createHandlers(db, getAuth(app), () => clock);
  env = await initializeTestEnvironment({ projectId, firestore: { host: '127.0.0.1', port: 8080,
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
  await env.clearFirestore();
  await db.doc('games/course').set({ published: true, name: 'Course', rules: 'Test rules', startsAt: now - 1000,
    endsAt: now + 86400000, durationSeconds: 3600, maxTeamSize: 2, requiresEntryCode: false,
    latitude: 41, longitude: 29, routes: [{ checkpointIds: ['one', 'two'] }] });
  await db.doc('games/course/checkpoints/one').set({ name: 'One', question: 'Direction?', options: ['North', 'South'],
    latitude: 41, longitude: 29, radiusMeters: 50, points: 100 });
  await db.doc('games/course/checkpoints/two').set({ name: 'Two', question: '2+2?', options: [],
    latitude: 41, longitude: 29, radiusMeters: 50, points: 100 });
  await db.doc('privateGames/course').set({ answers: { one: ['North'], two: ['4'] } });
  await db.doc('games/draft').set({ published: false });
  for (const uid of ['captain', 'mate', 'outsider', 'late', 'other', 'expiring']) await service.syncProfile(request(uid));
});

after(async () => { await env?.cleanup(); if (app) await deleteApp(app); });

let sessionId, joinCode;
test('anonymous and unverified players cannot call game operations', async () => {
  await assert.rejects(service.syncProfile({ data: {} }), { code: 'unauthenticated' });
  await assert.rejects(service.syncProfile(request('unverified', {}, { email_verified: false })), { code: 'permission-denied' });
});

test('create team writes a session and recoverable profile pointer atomically', async () => {
  const result = await service.createTeam(request('captain', { gameId: 'course', teamName: 'First team' }));
  sessionId = result.sessionId;
  const session = (await db.doc(`sessions/${sessionId}`).get()).data();
  joinCode = session.joinCode;
  assert.equal(session.status, 'waiting');
  assert.equal((await db.doc('users/captain').get()).data().activeSessionId, sessionId);
  assert.equal((await db.doc(`games/course/leaderboard/${sessionId}`).get()).exists, false);
});

test('a player cannot create two simultaneous active sessions', async () => {
  await assert.rejects(service.createTeam(request('captain', { gameId: 'course', teamName: 'Second' })), { code: 'failed-precondition' });
});

test('concurrent duplicate joins count the same member once', async () => {
  await Promise.all([service.joinTeam(request('mate', { joinCode })), service.joinTeam(request('mate', { joinCode }))]);
  const session = (await db.doc(`sessions/${sessionId}`).get()).data();
  assert.deepEqual(session.memberIds.sort(), ['captain', 'mate']);
  assert.equal((await db.doc('users/mate').get()).data().activeSessionId, sessionId);
});

test('full teams and invalid invite codes are rejected', async () => {
  await assert.rejects(service.joinTeam(request('outsider', { joinCode })), { code: 'resource-exhausted' });
  await assert.rejects(service.joinTeam(request('outsider', { joinCode: '../users' })), { code: 'invalid-argument' });
});

test('only the captain starts, with a server deadline and retry-safe state', async () => {
  await assert.rejects(service.startGame(request('mate', { sessionId })), { code: 'permission-denied' });
  await service.startGame(request('captain', { sessionId }));
  const started = (await db.doc(`sessions/${sessionId}`).get()).data();
  clock += 1000;
  await service.startGame(request('captain', { sessionId }));
  assert.equal((await db.doc(`sessions/${sessionId}`).get()).data().startedAt, started.startedAt);
  assert.equal(started.expiresAt, now + 3600000);
  clock = now;
  await assert.rejects(service.joinTeam(request('outsider', { joinCode })), { code: 'failed-precondition' });
});

test('nonmembers, wrong answers, and stale or distant GPS cannot earn points', async () => {
  const data = { sessionId, checkpointId: 'one', answer: 'North', location: fix };
  await assert.rejects(service.submitAnswer(request('outsider', data)), { code: 'permission-denied' });
  await assert.rejects(service.submitAnswer(request('mate', { ...data, answer: 'South' })), { code: 'failed-precondition' });
  await assert.rejects(service.submitAnswer(request('mate', { ...data, location: { ...fix, longitude: 28 } })), { code: 'failed-precondition' });
  await assert.rejects(service.submitAnswer(request('mate', { ...data, location: { ...fix, capturedAt: now - 60000 } })), { code: 'failed-precondition' });
  assert.equal((await db.doc(`sessions/${sessionId}`).get()).data().score, 0);
});

test('simultaneous correct answers earn points exactly once across teammates', async () => {
  const data = { sessionId, checkpointId: 'one', answer: '  north  ', location: fix };
  const results = await Promise.all([service.submitAnswer(request('captain', data)), service.submitAnswer(request('mate', data))]);
  assert.equal(results.filter(result => result.duplicate).length, 1);
  const session = (await db.doc(`sessions/${sessionId}`).get()).data();
  assert.equal(session.score, 100);
  assert.deepEqual(session.completedIds, ['one']);
  assert.equal((await db.doc(`games/course/leaderboard/${sessionId}`).get()).data().score, 100);
});

test('final checkpoint completes the whole team and a retry cannot duplicate points', async () => {
  const data = { sessionId, checkpointId: 'two', answer: '4', location: fix };
  await service.submitAnswer(request('mate', data));
  await service.submitAnswer(request('captain', data));
  const session = (await db.doc(`sessions/${sessionId}`).get()).data();
  assert.equal(session.status, 'completed');
  assert.equal(session.score, 200);
  assert.equal((await db.doc(`games/course/leaderboard/${sessionId}`).get()).data().status, 'completed');
});

test('Firestore rules reject public access, score forgery, private answers, and other profiles', async () => {
  const anonymous = env.unauthenticatedContext().firestore();
  const player = env.authenticatedContext('captain', { email_verified: true }).firestore();
  const unverified = env.authenticatedContext('captain', { email_verified: false }).firestore();
  await assertFails(getDoc(doc(anonymous, 'games/course')));
  await assertFails(getDoc(doc(unverified, 'games/course')));
  await assertSucceeds(getDoc(doc(player, 'games/course')));
  await assertFails(getDoc(doc(player, 'games/draft')));
  await assertFails(getDoc(doc(player, 'privateGames/course')));
  await assertFails(getDoc(doc(player, `joinCodes/${joinCode}`)));
  await assertFails(getDoc(doc(player, 'users/mate')));
  await assertSucceeds(getDoc(doc(player, 'users/captain')));
  await assertFails(updateDoc(doc(player, `sessions/${sessionId}`), { score: 9999 }));
  await assertFails(setDoc(doc(player, `games/course/leaderboard/${sessionId}`), { score: 9999 }));
  await assertFails(updateDoc(doc(player, 'users/captain'), { admin: true, activeSessionId: 'other' }));
});

test('only team members read a session and their own filtered history', async () => {
  const captain = env.authenticatedContext('captain', { email_verified: true }).firestore();
  const outsider = env.authenticatedContext('outsider', { email_verified: true }).firestore();
  await assertSucceeds(getDoc(doc(captain, `sessions/${sessionId}`)));
  await assertFails(getDoc(doc(outsider, `sessions/${sessionId}`)));
  await assertSucceeds(getDocs(query(collection(captain, 'sessions'), where('memberIds', 'array-contains', 'captain'))));
  await assertFails(getDocs(collection(captain, 'sessions')));
});

test('a lobby member can leave without ending the captain team', async () => {
  const { sessionId: lobbyId } = await service.createTeam(request('other', { gameId: 'course', teamName: 'Lobby' }));
  const code = (await db.doc(`sessions/${lobbyId}`).get()).data().joinCode;
  await service.joinTeam(request('late', { joinCode: code }));
  await service.leaveTeam(request('late', { sessionId: lobbyId }));
  const lobby = (await db.doc(`sessions/${lobbyId}`).get()).data();
  assert.deepEqual(lobby.memberIds, ['other']);
  assert.equal(lobby.status, 'waiting');
  assert.equal((await db.doc('users/late').get()).data().activeSessionId, null);
});

test('expiry rejects late answers even if the client missed its final timer tick', async () => {
  const { sessionId: expiringId } = await service.createTeam(request('expiring', { gameId: 'course', teamName: 'Clock test' }));
  await service.startGame(request('expiring', { sessionId: expiringId }));
  clock = now + 3600001;
  await assert.rejects(service.submitAnswer(request('expiring', { sessionId: expiringId, checkpointId: 'one', answer: 'North', location: { ...fix, capturedAt: clock } })), { code: 'failed-precondition' });
  await service.refreshSession(request('expiring', { sessionId: expiringId }));
  assert.equal((await db.doc(`sessions/${expiringId}`).get()).data().status, 'expired');
  assert.equal((await db.doc(`games/course/leaderboard/${expiringId}`).get()).data().elapsedSeconds, 3600);
  clock = now;
});

test('admin cancellation requires a signed custom claim, not a client password', async () => {
  const { sessionId: adminTestId } = await service.createTeam(request('late', { gameId: 'course', teamName: 'Admin test' }));
  await assert.rejects(service.adminEndSession(request('outsider', { sessionId: adminTestId, admin: true })), { code: 'permission-denied' });
  await service.adminEndSession(request('admin', { sessionId: adminTestId }, { admin: true }));
  assert.equal((await db.doc(`sessions/${adminTestId}`).get()).data().status, 'cancelled');
});

test('deployed callable protocol rejects unauthenticated requests', async () => {
  const result = await fetch('http://127.0.0.1:5001/demo-robert-compass/europe-west1/createTeam', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: { gameId: 'course', teamName: 'Unauthorized' } }),
  });
  assert.equal(result.status, 401);
  assert.equal((await result.json()).error.status, 'UNAUTHENTICATED');
});

test('account deletion requires recent sign-in and preserves anonymous shared results', async () => {
  const account = await getAuth(app).createUser({ email: 'delete-me@example.test', emailVerified: true });
  await service.syncProfile(request(account.uid));
  await db.doc('sessions/deletion-test').set({ gameId: 'course', ownerId: account.uid, memberIds: [account.uid],
    memberNames: { [account.uid]: 'Private name' }, status: 'completed', expiresAt: now - 1,
    startedAt: now - 10000, teamName: 'Private team', score: 100 });
  await db.doc('games/course/leaderboard/deletion-test').set({ teamName: 'Private team', score: 100 });
  await assert.rejects(service.deleteAccount(request(account.uid)), { code: 'unauthenticated' });
  await service.deleteAccount(request(account.uid, {}, { auth_time: now / 1000 }));
  await assert.rejects(getAuth(app).getUser(account.uid), { code: 'auth/user-not-found' });
  const session = (await db.doc('sessions/deletion-test').get()).data();
  assert.deepEqual(session.memberIds, []);
  assert.deepEqual(session.memberNames, {});
  assert.equal(session.teamName, 'Deleted team');
  assert.equal((await db.doc('games/course/leaderboard/deletion-test').get()).data().score, 100);
  await assert.rejects(service.syncProfile(request(account.uid)), { code: 'permission-denied' });
  await assert.rejects(service.createTeam(request(account.uid, { gameId: 'course', teamName: 'Race' })), { code: 'permission-denied' });
});

test('leaving an old expired lobby cannot clear a newer team reservation', async () => {
  await service.syncProfile(request('returning'));
  await service.syncProfile(request('old-captain'));
  const old = await service.createTeam(request('old-captain', { gameId: 'course', teamName: 'Old lobby' }));
  const code = (await db.doc(`sessions/${old.sessionId}`).get()).data().joinCode;
  await service.joinTeam(request('returning', { joinCode: code }));
  clock = now + 3600001;
  const current = await service.createTeam(request('returning', { gameId: 'course', teamName: 'New lobby' }));
  await service.leaveTeam(request('returning', { sessionId: old.sessionId }));
  assert.equal((await db.doc('users/returning').get()).data().activeSessionId, current.sessionId);
  await assert.rejects(service.createTeam(request('returning', { gameId: 'course', teamName: 'Forbidden third' })), { code: 'failed-precondition' });
  clock = now;
});
