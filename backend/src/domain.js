/**
 * Pure validation and scoring rules shared by the callable service and tests.
 * Keeping clock and location inputs explicit makes retries and expiry deterministic.
 * @module domain
 * @example validateLocation(checkpoint, fix, Date.now());
 */
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Reject a violated business rule with a client-safe callable error.
 * @param {boolean} condition Whether the invariant holds.
 * @param {string} code Firebase callable status code.
 * @param {string} message Actionable message without private data.
 * @returns {void}
 * @throws {HttpsError} When the condition is false.
 * @example ensure(session.status === 'active', 'failed-precondition', 'Start first.');
 */
export function ensure(condition, code, message) {
  if (!condition) throw new HttpsError(code, message);
}

/**
 * Validate bounded input text before using it in documents or identifiers.
 * @param {unknown} value Supplied value.
 * @param {string} label User-facing field name.
 * @param {number} max Maximum trimmed length.
 * @returns {string} Trimmed nonempty text.
 * @throws {HttpsError} For missing, oversized, or control-character input.
 * @example text(' Team A ', 'Team name', 60);
 */
export function text(value, label, max = 100) {
  ensure(typeof value === 'string', 'invalid-argument', `${label} is required.`);
  const result = value.trim();
  ensure(result.length > 0 && result.length <= max && !/[\u0000-\u001f\u007f]/u.test(result),
    'invalid-argument', `${label} is invalid.`);
  return result;
}

/**
 * Validate a single Firestore document identifier, never a path.
 * @param {unknown} value Supplied identifier.
 * @returns {string} Safe identifier.
 * @throws {HttpsError} For path separators or invalid text.
 * @example id('campus-course');
 */
export function id(value) {
  const result = text(value, 'Identifier', 128);
  ensure(/^[A-Za-z0-9_-]+$/u.test(result), 'invalid-argument', 'Identifier is invalid.');
  return result;
}

/**
 * Normalize answers without changing accented letters or punctuation.
 * @param {string} value Answer text.
 * @returns {string} Unicode-normalized, trimmed, case-insensitive answer.
 * @throws {TypeError} If called without a string by internal code.
 * @example normalizeAnswer('  North  ') === 'north';
 */
export function normalizeAnswer(value) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ').toLocaleLowerCase('en-US');
}

/**
 * Compute great-circle distance in meters with the haversine formula.
 * @param {{latitude:number, longitude:number}} a First coordinate.
 * @param {{latitude:number, longitude:number}} b Second coordinate.
 * @returns {number} Distance in meters.
 * @throws {Error} None; callers validate coordinate ranges first.
 * @example distanceMeters({latitude:0,longitude:0}, {latitude:0,longitude:0});
 */
export function distanceMeters(a, b) {
  const rad = Math.PI / 180;
  const deltaLat = (b.latitude - a.latitude) * rad;
  const deltaLon = (b.longitude - a.longitude) * rad;
  const h = Math.sin(deltaLat / 2) ** 2 + Math.cos(a.latitude * rad) *
    Math.cos(b.latitude * rad) * Math.sin(deltaLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}

/**
 * Require a recent, accurate location within a checkpoint's configured radius.
 * Client GPS is an eligibility signal, not proof against a compromised device.
 * @param {{latitude:number,longitude:number,radiusMeters:number}} checkpoint Target.
 * @param {object} fix Client location with accuracy and capturedAt in epoch milliseconds.
 * @param {number} now Trusted server time in epoch milliseconds.
 * @returns {void}
 * @throws {HttpsError} For stale, inaccurate, invalid, or distant location.
 * @example validateLocation(point, fix, Date.now());
 */
export function validateLocation(checkpoint, fix, now) {
  ensure(fix && typeof fix === 'object', 'invalid-argument', 'A current location is required.');
  const { latitude, longitude, accuracy, capturedAt } = fix;
  ensure([latitude, longitude, accuracy, capturedAt].every(Number.isFinite) &&
    Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180,
  'invalid-argument', 'Location is invalid.');
  ensure(accuracy >= 0 && accuracy <= Math.min(checkpoint.radiusMeters, 50),
    'failed-precondition', 'GPS accuracy is too low. Enable Precise Location and try outdoors.');
  ensure(capturedAt <= now + 5000 && now - capturedAt <= 30000,
    'failed-precondition', 'Location is out of date. Try again.');
  ensure(distanceMeters(checkpoint, fix) <= checkpoint.radiusMeters,
    'failed-precondition', `Move within ${checkpoint.radiusMeters} meters of this checkpoint.`);
}

/**
 * Determine whether a session still reserves its members.
 * @param {object|undefined} session Stored session.
 * @param {number} now Trusted time in milliseconds.
 * @returns {boolean} True for an unexpired lobby or active game.
 * @throws {Error} None.
 * @example isOpen(session, Date.now());
 */
export function isOpen(session, now) {
  return !!session && ['waiting', 'active'].includes(session.status) && session.expiresAt > now;
}

/**
 * Derive the public leaderboard entry without exposing member IDs or invite codes.
 * @param {object} session Authoritative session state.
 * @param {number} now Trusted time in milliseconds.
 * @returns {object} Public score projection.
 * @throws {Error} None.
 * @example leaderboardEntry(session, Date.now());
 */
export function leaderboardEntry(session, now) {
  return {
    teamName: session.teamName,
    score: session.score,
    status: session.status,
    elapsedSeconds: session.startedAt ? Math.max(0, Math.floor((Math.min(now, session.expiresAt) - session.startedAt) / 1000)) : 0,
    updatedAt: now,
  };
}
