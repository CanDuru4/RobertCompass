/**
 * Transactional team lifecycle and scoring service.
 * Only this server boundary writes sessions, profiles, and leaderboard projections.
 * @module service
 * @example const handlers = createHandlers(firestore, auth);
 */
import { randomBytes, randomInt, createHash } from 'node:crypto';
import { ensure, id, text, normalizeAnswer, validateLocation, isOpen, leaderboardEntry } from './domain.js';

/**
 * Construct callable handlers with injectable storage and clock dependencies.
 * Firestore transactions serialize simultaneous joins and answers from teammates.
 * @param {import('firebase-admin/firestore').Firestore} db Database adapter.
 * @param {import('firebase-admin/auth').Auth} auth Account administration adapter.
 * @param {() => number} clock Server epoch milliseconds.
 * @returns {Record<string, Function>} Verified-user callable handlers.
 * @throws {HttpsError} Handlers reject invalid input, unauthorized access, and expired games.
 * @example createHandlers(getFirestore(), getAuth());
 */
export function createHandlers(db, auth, clock = Date.now) {
  const userRef = uid => db.collection('users').doc(uid);
  const sessionRef = value => db.collection('sessions').doc(id(value));
  const gameRef = value => db.collection('games').doc(id(value));
  const boardRef = (gameId, sessionId) => gameRef(gameId).collection('leaderboard').doc(sessionId);

  function identity(request) {
    ensure(request.auth?.uid, 'unauthenticated', 'Sign in to continue.');
    ensure(request.auth.token.email_verified === true, 'permission-denied', 'Verify your email first.');
    return request.auth.uid;
  }

  function member(session, uid) {
    ensure(session?.memberIds?.includes(uid), 'permission-denied', 'You are not a member of this team.');
  }

  async function checkAvailability(tx, uid, now, allowedId = '') {
    const profile = (await tx.get(userRef(uid))).data();
    ensure(!profile?.deleting, 'permission-denied', 'This account is being deleted.');
    if (profile?.activeSessionId && profile.activeSessionId !== allowedId) {
      const previous = (await tx.get(sessionRef(profile.activeSessionId))).data();
      ensure(!isOpen(previous, now), 'failed-precondition', 'Finish or leave your current team first.');
    }
  }

  const handlers = {
    async syncProfile(request) {
      const uid = identity(request);
      const name = text(request.data?.displayName || request.auth.token.name || 'Player', 'Display name', 60);
      await db.runTransaction(async tx => {
        const profile = (await tx.get(userRef(uid))).data();
        ensure(!profile?.deleting, 'permission-denied', 'This account is being deleted.');
        tx.set(userRef(uid), { displayName: name, updatedAt: clock() }, { merge: true });
      });
      return { ok: true };
    },

    async createTeam(request) {
      const uid = identity(request);
      const gameId = id(request.data?.gameId);
      const teamName = text(request.data?.teamName, 'Team name', 60);
      const entryCode = request.data?.entryCode ?? '';
      ensure(typeof entryCode === 'string' && entryCode.length <= 128, 'invalid-argument', 'Entry code is invalid.');
      const ref = db.collection('sessions').doc();
      const joinCode = randomBytes(6).toString('hex').toUpperCase();
      const invite = db.collection('joinCodes').doc(joinCode);
      await db.runTransaction(async tx => {
        const now = clock();
        const [gameDoc, privateDoc, profileDoc, inviteDoc] = await tx.getAll(
          gameRef(gameId), db.collection('privateGames').doc(gameId), userRef(uid), invite);
        const game = gameDoc.data();
        ensure(game?.published && game.endsAt > now, 'failed-precondition', 'This course is not available.');
        ensure(privateDoc.exists, 'failed-precondition', 'The organizer has not finished setting up this course.');
        ensure(!inviteDoc.exists, 'aborted', 'Please try creating your team again.');
        const expectedHash = privateDoc.data().entryCodeHash;
        ensure(!expectedHash || createHash('sha256').update(entryCode).digest('hex') === expectedHash,
          'permission-denied', 'The course entry code is incorrect.');
        await checkAvailability(tx, uid, now);
        const session = {
          gameId, gameName: game.name, teamName, ownerId: uid,
          memberIds: [uid], memberNames: { [uid]: profileDoc.data()?.displayName || 'Player' },
          joinCode, createdAt: now, expiresAt: Math.min(now + 3600000, game.endsAt),
          startedAt: null, finishedAt: null, status: 'waiting', score: 0,
          completedIds: [], checkpointIds: [],
        };
        tx.create(ref, session);
        tx.create(invite, { sessionId: ref.id });
        tx.set(userRef(uid), { activeSessionId: ref.id }, { merge: true });
      });
      return { sessionId: ref.id };
    },

    async joinTeam(request) {
      const uid = identity(request);
      const code = text(request.data?.joinCode, 'Team code', 12).toUpperCase();
      ensure(/^[A-F0-9]{12}$/u.test(code), 'invalid-argument', 'Enter the 12-character team code.');
      return db.runTransaction(async tx => {
        const now = clock();
        const invite = await tx.get(db.collection('joinCodes').doc(code));
        ensure(invite.exists, 'not-found', 'Team code not found.');
        const ref = sessionRef(invite.data().sessionId);
        const session = (await tx.get(ref)).data();
        ensure(session && isOpen(session, now) && session.status === 'waiting',
          'failed-precondition', 'This team has already started or expired.');
        const game = (await tx.get(gameRef(session.gameId))).data();
        ensure(game?.published && game.endsAt > now, 'failed-precondition', 'This course is unavailable.');
        if (session.memberIds.includes(uid)) return { sessionId: ref.id };
        ensure(session.memberIds.length < game.maxTeamSize, 'resource-exhausted', 'This team is full.');
        const profile = (await tx.get(userRef(uid))).data();
        await checkAvailability(tx, uid, now, ref.id);
        tx.update(ref, {
          memberIds: [...session.memberIds, uid],
          memberNames: { ...session.memberNames, [uid]: profile?.displayName || 'Player' },
        });
        tx.set(userRef(uid), { activeSessionId: ref.id }, { merge: true });
        return { sessionId: ref.id };
      });
    },

    async startGame(request) {
      const uid = identity(request);
      const ref = sessionRef(request.data?.sessionId);
      await db.runTransaction(async tx => {
        const now = clock();
        const session = (await tx.get(ref)).data();
        member(session, uid);
        ensure(session.ownerId === uid, 'permission-denied', 'Only the team captain can start.');
        if (session.status === 'active' && session.expiresAt > now) return;
        ensure(session.status === 'waiting' && session.expiresAt > now,
          'failed-precondition', 'This team lobby has expired.');
        const game = (await tx.get(gameRef(session.gameId))).data();
        ensure(game?.published && game.startsAt <= now && game.endsAt > now,
          'failed-precondition', 'The course is outside its scheduled time.');
        const routes = game.routes;
        ensure(Array.isArray(routes) && routes.length > 0, 'failed-precondition', 'This course has no routes.');
        const route = routes[randomInt(routes.length)].checkpointIds;
        ensure(Array.isArray(route) && route.length > 0 && route.length <= 100,
          'failed-precondition', 'This course route is invalid.');
        const updated = { ...session, status: 'active', checkpointIds: route,
          startedAt: now, expiresAt: Math.min(now + game.durationSeconds * 1000, game.endsAt) };
        tx.update(ref, updated);
        tx.set(boardRef(session.gameId, ref.id), leaderboardEntry(updated, now));
      });
      return { ok: true, serverTime: clock() };
    },

    async submitAnswer(request) {
      const uid = identity(request);
      const ref = sessionRef(request.data?.sessionId);
      const checkpointId = id(request.data?.checkpointId);
      const answer = text(request.data?.answer, 'Answer', 300);
      return db.runTransaction(async tx => {
        const now = clock();
        const session = (await tx.get(ref)).data();
        member(session, uid);
        ensure(session.checkpointIds.includes(checkpointId), 'permission-denied', 'Checkpoint is not in your route.');
        if (session.completedIds.includes(checkpointId)) return { accepted: true, duplicate: true, score: session.score };
        ensure(session.status === 'active' && session.expiresAt > now,
          'failed-precondition', 'This activity has ended.');
        const [pointDoc, privateDoc] = await tx.getAll(
          gameRef(session.gameId).collection('checkpoints').doc(checkpointId),
          db.collection('privateGames').doc(session.gameId));
        ensure(pointDoc.exists && privateDoc.exists, 'failed-precondition', 'Checkpoint is unavailable.');
        const point = pointDoc.data();
        validateLocation(point, request.data?.location, now);
        const answers = privateDoc.data().answers?.[checkpointId];
        ensure(Array.isArray(answers) && answers.some(value => normalizeAnswer(value) === normalizeAnswer(answer)),
          'failed-precondition', 'That answer is not correct. Try again.');
        const completedIds = [...session.completedIds, checkpointId];
        const complete = completedIds.length === session.checkpointIds.length;
        const updated = { ...session, completedIds, score: session.score + point.points,
          status: complete ? 'completed' : 'active', finishedAt: complete ? now : null };
        tx.update(ref, updated);
        tx.set(boardRef(session.gameId, ref.id), leaderboardEntry(updated, now));
        return { accepted: true, duplicate: false, score: updated.score };
      });
    },

    async refreshSession(request) {
      const uid = identity(request);
      const ref = sessionRef(request.data?.sessionId);
      await db.runTransaction(async tx => {
        const now = clock();
        const session = (await tx.get(ref)).data();
        member(session, uid);
        if (['waiting', 'active'].includes(session.status) && session.expiresAt <= now) {
          const updated = { ...session, status: 'expired', finishedAt: session.expiresAt };
          tx.update(ref, updated);
          if (session.startedAt) tx.set(boardRef(session.gameId, ref.id), leaderboardEntry(updated, session.expiresAt));
        }
      });
      return { serverTime: clock() };
    },

    async leaveTeam(request) {
      const uid = identity(request);
      const ref = sessionRef(request.data?.sessionId);
      await db.runTransaction(async tx => {
        const now = clock();
        const session = (await tx.get(ref)).data();
        member(session, uid);
        const isAdmin = request.auth.token.admin === true;
        if (session.status === 'waiting' && session.ownerId !== uid) {
          const profile = (await tx.get(userRef(uid))).data();
          const names = { ...session.memberNames };
          delete names[uid];
          tx.update(ref, { memberIds: session.memberIds.filter(value => value !== uid), memberNames: names });
          if (profile?.activeSessionId === ref.id) tx.set(userRef(uid), { activeSessionId: null }, { merge: true });
          return;
        }
        ensure(session.ownerId === uid || isAdmin, 'permission-denied', 'Ask your team captain to end the activity.');
        if (!isOpen(session, now)) return;
        const updated = { ...session, status: 'cancelled', finishedAt: now };
        tx.update(ref, updated);
        if (session.startedAt) tx.set(boardRef(session.gameId, ref.id), leaderboardEntry(updated, now));
      });
      return { ok: true };
    },

    async adminEndSession(request) {
      identity(request);
      ensure(request.auth.token.admin === true, 'permission-denied', 'Administrator access is required.');
      const ref = sessionRef(request.data?.sessionId);
      await db.runTransaction(async tx => {
        const session = (await tx.get(ref)).data();
        ensure(session, 'not-found', 'Activity not found.');
        if (!isOpen(session, clock())) return;
        const updated = { ...session, status: 'cancelled', finishedAt: clock() };
        tx.update(ref, updated);
        if (session.startedAt) tx.set(boardRef(session.gameId, ref.id), leaderboardEntry(updated, clock()));
      });
      return { ok: true };
    },

    async deleteAccount(request) {
      const uid = identity(request);
      ensure(Number.isFinite(request.auth.token.auth_time) && clock() / 1000 - request.auth.token.auth_time < 300,
        'unauthenticated', 'Sign in again before deleting your account.');
      await db.runTransaction(async tx => {
        const profile = (await tx.get(userRef(uid))).data();
        if (profile?.activeSessionId) {
          const current = (await tx.get(sessionRef(profile.activeSessionId))).data();
          ensure(!isOpen(current, clock()), 'failed-precondition', 'Leave or finish your current team before deleting your account.');
        }
        tx.set(userRef(uid), { deleting: true, deletedAt: clock() });
      });
      let page;
      do {
        page = await db.collection('sessions').where('memberIds', 'array-contains', uid).limit(100).get();
        for (const document of page.docs) {
          await db.runTransaction(async tx => {
            const stored = (await tx.get(document.ref)).data();
            const names = { ...stored.memberNames };
            delete names[uid];
            const memberIds = stored.memberIds.filter(value => value !== uid);
            const update = { memberIds, memberNames: names,
              ownerId: stored.ownerId === uid ? (memberIds[0] ?? 'deleted') : stored.ownerId };
            if (memberIds.length === 0) update.teamName = 'Deleted team';
            tx.update(document.ref, update);
            if (memberIds.length === 0 && stored.startedAt) tx.set(boardRef(stored.gameId, document.id), { teamName: 'Deleted team' }, { merge: true });
          });
        }
      } while (!page.empty);
      await auth.deleteUser(uid);
      return { ok: true };
    },
  };
  return handlers;
}
