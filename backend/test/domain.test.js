import test from 'node:test';
import assert from 'node:assert/strict';
import { id, text, normalizeAnswer } from '../src/domain.js';

test('IDs reject document paths and control characters', () => {
  assert.equal(id('north-gate_2'), 'north-gate_2');
  for (const value of ['../users/admin', 'foo/bar', '', '\n', 123]) assert.throws(() => id(value));
});

test('answers normalize whitespace and Unicode without dropping accents', () => {
  assert.equal(normalizeAnswer('  NORTH   gate  '), 'north gate');
  assert.equal(normalizeAnswer('Ｃｏｍｐａｓｓ'), 'compass');
  assert.notEqual(normalizeAnswer('café'), normalizeAnswer('cafe'));
});

test('organizer validation preserves bounded text and actionable error codes', () => {
  assert.equal(text('  Team A  ', 'Name', 6), 'Team A');
  for (const value of ['', 123, 'too long', 'line\nfeed']) {
    assert.throws(() => text(value, 'Name', 6), { code: 'invalid-argument', name: 'Error' });
  }
});
