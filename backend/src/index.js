/**
 * Firebase callable deployment entry points for Robert Compass.
 * Production calls require App Check; emulator access remains loopback-only.
 * @module index
 * @example firebase deploy --only functions:compass --project YOUR_PROJECT_ID
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2';
import { createHandlers } from './service.js';

initializeApp();
setGlobalOptions({ region: 'europe-west1', maxInstances: 3, memory: '256MiB', timeoutSeconds: 30 });
const handlers = createHandlers(getFirestore(), getAuth());
const options = { enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== 'true' };

function callable(handler) {
  return onCall(options, async request => {
    if (request.auth?.uid) {
      try {
        const account = await getAuth().getUser(request.auth.uid);
        if (account.disabled) throw new Error('disabled');
      } catch {
        throw new HttpsError('unauthenticated', 'Your account is unavailable. Sign in again.');
      }
    }
    return handler(request);
  });
}

export const syncProfile = callable(handlers.syncProfile);
export const createTeam = callable(handlers.createTeam);
export const joinTeam = callable(handlers.joinTeam);
export const startGame = callable(handlers.startGame);
export const submitAnswer = callable(handlers.submitAnswer);
export const refreshSession = callable(handlers.refreshSession);
export const leaveTeam = callable(handlers.leaveTeam);
export const adminEndSession = callable(handlers.adminEndSession);
export const deleteAccount = callable(handlers.deleteAccount);
