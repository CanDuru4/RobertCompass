/**
 * Coordinate one explicitly tagged physical-device acceptance test on live Firebase.
 * The phone creates its own random password; this helper never receives it.
 * @module device-fixture
 * @example node scripts/device-fixture.js --tag 0123456789abcdef --apply
 */
import assert from 'node:assert/strict';
import { parseArgs } from 'node:util';
import { access } from 'node:fs/promises';
import { setTimeout as pause } from 'node:timers/promises';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { firebaseCLICredential, ownerFirestore } from './owner-credentials.js';

const { values } = parseArgs({ options: { tag: { type: 'string' }, apply: { type: 'boolean' } } });
assert.match(values.tag ?? '', /^[a-f0-9]{16}$/);
assert.equal(values.apply, true);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, undefined);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, undefined);
const tag = values.tag;
const projectId = 'robert-compass';
const email = `compass-device-${tag}@example.test`;
const gameId = `qa-device-${tag}`;
const stopFile = new URL(`../../build/device-qa-finished-${tag}`, import.meta.url);
const owner = initializeApp({ projectId, credential: await firebaseCLICredential() });
const auth = getAuth(owner);
const db = await ownerFirestore(projectId);
const course = db.doc(`games/${gameId}`);
let prepared = false;
let uid;

try {
  await assert.rejects(auth.getUserByEmail(email), error => error.code === 'auth/user-not-found');
  const batch = db.batch();
  batch.create(course, { name: 'Device connection check (temporary)', rules: 'Automated connection check, not a playable course.',
    published: true, startsAt: Date.now() - 1000, endsAt: Date.now() + 600000, durationSeconds: 300,
    maxTeamSize: 1, latitude: 41, longitude: 29, requiresEntryCode: false, routes: [{ checkpointIds: ['point'] }] });
  batch.create(course.collection('checkpoints').doc('point'), { name: 'Device check', question: 'Test input', options: [],
    latitude: 41, longitude: 29, radiusMeters: 50, points: 100 });
  batch.create(db.doc(`privateGames/${gameId}`), { answers: { point: ['correct'] }, entryCodeHash: null });
  await batch.commit();
  prepared = true;
  console.log('Physical-device fixture ready. Waiting for its exact temporary account.');
  const deadline = Date.now() + 240000;
  while (Date.now() < deadline) {
    if (await access(stopFile).then(() => true, () => false)) break;
    try {
      const user = await auth.getUserByEmail(email);
      uid = user.uid;
      if (!user.emailVerified) { await auth.updateUser(uid, { emailVerified: true }); console.log('Temporary device account verified.'); }
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      if (uid) { console.log('The phone deleted its temporary account after testing.'); break; }
    }
    await pause(1000);
  }
} catch (error) {
  console.error('Device fixture failed:', error.code ?? error.name ?? 'unknown');
  process.exitCode = 1;
} finally {
  if (prepared) {
    const cleanup = db.batch();
    if (uid) {
      const sessions = await db.collection('sessions').where('gameId', '==', gameId).get();
      for (const session of sessions.docs) {
        const s = session.data();
        assert.ok(s.ownerId === uid || s.ownerId === '' && s.memberIds.length === 0);
        cleanup.delete(session.ref);
        cleanup.delete(db.doc(`joinCodes/${s.joinCode}`));
        cleanup.delete(course.collection('leaderboard').doc(session.id));
      }
      for (const collection of ['attempts', 'entries']) {
        const items = await db.collection(`users/${uid}/${collection}`).get();
        items.docs.forEach(document => cleanup.delete(document.ref));
      }
      cleanup.delete(db.doc(`users/${uid}`));
      try { await auth.deleteUser(uid); } catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    }
    cleanup.delete(course.collection('checkpoints').doc('point'));
    cleanup.delete(db.doc(`privateGames/${gameId}`));
    cleanup.delete(course);
    await cleanup.commit();
    console.log('Temporary physical-device fixtures cleaned up.');
  }
  await db.terminate();
}
