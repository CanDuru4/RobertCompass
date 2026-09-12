import test from 'node:test';
import assert from 'node:assert/strict';
import { id, normalizeAnswer, distanceMeters, validateLocation, isOpen, leaderboardEntry } from '../src/domain.js';

test('IDs reject document paths and control characters', () => {
  assert.equal(id('north-gate_2'), 'north-gate_2');
  for (const value of ['../users/admin', 'foo/bar', '', '\n', 123]) assert.throws(() => id(value));
});

test('answers normalize whitespace and Unicode without dropping accents', () => {
  assert.equal(normalizeAnswer('  NORTH   gate  '), 'north gate');
  assert.equal(normalizeAnswer('Ｃｏｍｐａｓｓ'), 'compass');
  assert.notEqual(normalizeAnswer('café'), normalizeAnswer('cafe'));
});

test('distance uses meters and crosses longitude boundaries correctly', () => {
  assert.equal(distanceMeters({ latitude: 41, longitude: 29 }, { latitude: 41, longitude: 29 }), 0);
  const distance = distanceMeters({ latitude: 0, longitude: 179.999 }, { latitude: 0, longitude: -179.999 });
  assert.ok(distance > 222 && distance < 223);
});

test('GPS checks reject stale, inaccurate, nonfinite, and distant samples', () => {
  const now = 1000000;
  const point = { latitude: 41, longitude: 29, radiusMeters: 40 };
  const fix = { latitude: 41, longitude: 29, accuracy: 10, capturedAt: now };
  validateLocation(point, fix, now);
  for (const change of [{ accuracy: -1 }, { accuracy: 51 }, { capturedAt: now - 31000 },
    { capturedAt: now + 6000 }, { latitude: NaN }, { latitude: 91 }, { longitude: 28 }]) {
    assert.throws(() => validateLocation(point, { ...fix, ...change }, now));
  }
});

test('deadlines work at midnight and exact expiry without waiting for a zero tick', () => {
  const deadline = Date.parse('2026-09-13T00:00:00Z');
  const session = { status: 'active', expiresAt: deadline };
  assert.equal(isOpen(session, deadline - 1), true);
  assert.equal(isOpen(session, deadline), false);
  assert.equal(isOpen(session, deadline + 15000), false);
  assert.equal(isOpen({ ...session, status: 'completed' }, deadline - 1), false);
});

test('leaderboard excludes private membership and clips elapsed time at expiry', () => {
  const row = leaderboardEntry({ teamName: 'Team', score: 100, status: 'expired', startedAt: 1000,
    expiresAt: 61000, memberIds: ['private-user'], joinCode: 'private-code' }, 120000);
  assert.equal(row.elapsedSeconds, 60);
  assert.equal(row.score, 100);
  assert.equal('memberIds' in row, false);
  assert.equal('joinCode' in row, false);
});
