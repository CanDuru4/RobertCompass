/**
 * Create a disposable, verified player for automated simulator tests.
 * This script refuses live projects and never sends a real verification email.
 * @module prepare-ui
 * @example node scripts/prepare-ui.js
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
initializeApp({ projectId: 'demo-robert-compass' });
const auth = getAuth();
const data = { email: 'ui-player@compass.example.test', password: 'Emulator-only-Compass-123!', emailVerified: true, displayName: 'Simulator Player' };
try {
  const account = await auth.getUserByEmail(data.email);
  await auth.updateUser(account.uid, data);
} catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
  await auth.createUser(data);
}
console.log('Disposable simulator player ready.');
