/**
 * Create an explicitly named course without overwriting an existing course.
 * With no arguments, this command only seeds the loopback demo emulator.
 * @module seed
 * @example node scripts/seed.js --project YOUR_PROJECT_ID --file /absolute/course.json --apply
 */
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { createHash } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { id, text, ensure, normalizeAnswer } from '../src/domain.js';

const { values } = parseArgs({ options: {
  project: { type: 'string' }, file: { type: 'string' }, apply: { type: 'boolean', default: false },
  'firebase-cli': { type: 'boolean', default: false },
} });
const projectId = values.project ?? 'demo-robert-compass';
const local = projectId === 'demo-robert-compass';
ensure(local || !process.env.FIRESTORE_EMULATOR_HOST, 'invalid-argument', 'Remove emulator settings before selecting a live project.');
ensure(local || values.file, 'invalid-argument', 'A live project requires an explicit course file.');
if (local) process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const now = Date.now();
const input = values.file ? JSON.parse(await readFile(values.file, 'utf8')) : {
  id: 'practice-course', name: 'Practice course (sample)',
  rules: 'This is sample data for testing. These coordinates are not a verified Robert College route. Visit each marked checkpoint and answer its question. Each answer earns 100 points for your whole team.',
  startsAt: now - 3600000, endsAt: now + 86400000, durationSeconds: 3600, maxTeamSize: 4,
  latitude: 41, longitude: 29, published: true, routes: [['north', 'east']],
  checkpoints: [
    { id: 'north', name: 'North checkpoint (sample)', question: 'Which direction is opposite south?', options: ['North', 'East', 'West'], answers: ['North'], latitude: 41, longitude: 29, radiusMeters: 50, points: 100 },
    { id: 'east', name: 'East checkpoint (sample)', question: 'What is 2 + 2?', options: [], answers: ['4', 'four'], latitude: 41.0002, longitude: 29.0002, radiusMeters: 50, points: 100 },
  ],
};
const courseId = id(input.id);
text(input.name, 'Course name', 100);
ensure(typeof input.rules === 'string' && input.rules.trim().length > 0 && input.rules.length <= 10000,
  'invalid-argument', 'Rules must contain 1 to 10000 characters.');
ensure(Number.isSafeInteger(input.startsAt) && Number.isSafeInteger(input.endsAt) && input.endsAt > input.startsAt,
  'invalid-argument', 'Course dates must be epoch milliseconds and end after the start.');
ensure(Number.isInteger(input.durationSeconds) && input.durationSeconds >= 60 && input.durationSeconds <= 86400,
  'invalid-argument', 'Duration must be 60 to 86400 seconds.');
ensure(Number.isInteger(input.maxTeamSize) && input.maxTeamSize >= 1 && input.maxTeamSize <= 20,
  'invalid-argument', 'Team size must be 1 to 20.');
ensure(Number.isFinite(input.latitude) && Math.abs(input.latitude) <= 90 && Number.isFinite(input.longitude) && Math.abs(input.longitude) <= 180,
  'invalid-argument', 'Course coordinates are invalid.');
ensure(Array.isArray(input.checkpoints) && input.checkpoints.length > 0 && input.checkpoints.length <= 100,
  'invalid-argument', 'Provide 1 to 100 checkpoints.');
const pointIds = new Set();
const answers = {};
for (const point of input.checkpoints) {
  id(point.id);
  ensure(!pointIds.has(point.id), 'invalid-argument', 'Checkpoint IDs must be unique.');
  pointIds.add(point.id);
  text(point.name, 'Checkpoint name', 100);
  text(point.question, 'Question', 1000);
  ensure(Array.isArray(point.answers) && point.answers.length > 0 && point.answers.length <= 20,
    'invalid-argument', 'Each checkpoint needs accepted answers.');
  point.answers.forEach(answer => text(answer, 'Answer', 300));
  ensure(Array.isArray(point.options) && point.options.length <= 8, 'invalid-argument', 'Use at most 8 choices.');
  point.options.forEach(option => text(option, 'Choice', 300));
  ensure(Number.isFinite(point.latitude) && Math.abs(point.latitude) <= 90 && Number.isFinite(point.longitude) && Math.abs(point.longitude) <= 180 &&
    Number.isFinite(point.radiusMeters) && point.radiusMeters >= 10 && point.radiusMeters <= 500 &&
    Number.isInteger(point.points) && point.points > 0 && point.points <= 10000,
  'invalid-argument', 'Checkpoint location, radius, or points are invalid.');
  answers[point.id] = point.answers.map(normalizeAnswer);
}
ensure(Array.isArray(input.routes) && input.routes.length > 0 && input.routes.length <= 20,
  'invalid-argument', 'Provide 1 to 20 routes.');
for (const route of input.routes) {
  ensure(Array.isArray(route) && route.length > 0 && new Set(route).size === route.length && route.every(pointId => pointIds.has(pointId)),
    'invalid-argument', 'Routes must contain unique, existing checkpoint IDs.');
}
ensure(input.entryCode === undefined || typeof input.entryCode === 'string' && input.entryCode.length <= 128,
  'invalid-argument', 'Entry code is invalid.');
const { checkpoints, entryCode } = input;
const course = {
  name: input.name, rules: input.rules, startsAt: input.startsAt, endsAt: input.endsAt,
  durationSeconds: input.durationSeconds, maxTeamSize: input.maxTeamSize,
  latitude: input.latitude, longitude: input.longitude,
  routes: input.routes.map(checkpointIds => ({ checkpointIds })),
  published: input.published === true, requiresEntryCode: !!entryCode,
};
if (!local && !values.apply) {
  console.log(`Validated ${checkpoints.length} checkpoints for ${projectId}/${courseId}. Add --apply to create this course.`);
} else {
  const db = !local && values['firebase-cli']
    ? await (await import('./owner-credentials.js')).ownerFirestore(projectId)
    : getFirestore(initializeApp({ projectId }));
  const batch = db.batch();
  const ref = db.collection('games').doc(courseId);
  batch.create(ref, course);
  batch.create(db.collection('privateGames').doc(courseId), {
    answers, entryCodeHash: entryCode ? createHash('sha256').update(entryCode).digest('hex') : null,
  });
  for (const point of checkpoints) batch.create(ref.collection('checkpoints').doc(point.id), {
    name: point.name, question: point.question, options: point.options,
    latitude: point.latitude, longitude: point.longitude, radiusMeters: point.radiusMeters, points: point.points,
  });
  await batch.commit();
  console.log(`Created course ${courseId} in ${projectId}.`);
}
