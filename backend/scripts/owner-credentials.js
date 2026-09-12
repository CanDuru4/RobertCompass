/**
 * Reuse an explicitly authorized, local Firebase CLI account for organizer imports.
 * The pinned CLI handles refresh and storage; credentials never enter app files.
 * @module owner-credentials
 * @example initializeApp({ projectId, credential: await firebaseCLICredential() });
 */
import { createRequire } from 'node:module';
import { Firestore } from '@google-cloud/firestore';
import { OAuth2Client } from 'google-auth-library';

/**
 * Adapt the pinned Firebase CLI login to Firebase Admin's credential contract.
 * This is opt-in tooling, avoids service-account keys, and never logs tokens.
 * @returns {Promise<{getAccessToken: Function}>} An in-memory Admin credential.
 * @throws {Error} When the selected local CLI account is not authorized.
 * @example const credential = await firebaseCLICredential();
 */
export async function firebaseCLICredential() {
  const require = createRequire(import.meta.url);
  const auth = require('firebase-tools/lib/auth.js');
  const { requireAuth } = require('firebase-tools/lib/requireAuth.js');
  const account = auth.getProjectDefaultAccount(process.cwd());
  if (!account?.tokens?.refresh_token) throw new Error('Authorize the local Firebase CLI before importing a course.');
  await requireAuth({ ...account, nonInteractive: true }, true);
  return {
    async getAccessToken() {
      const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
      return { access_token: token.access_token, expires_in: Math.max(1, Math.floor((token.expires_at - Date.now()) / 1000)) };
    },
  };
}

/**
 * Open organizer Firestore access with the same authorized CLI account.
 * Firestore requires a Google auth client rather than an Admin credential adapter.
 * @param {string} projectId Explicit owner-controlled Firebase project identifier.
 * @returns {Promise<Firestore>} A database client with in-memory OAuth refresh.
 * @throws {Error} When CLI authorization or the initial token refresh fails.
 * @example const db = await ownerFirestore('robert-compass');
 */
export async function ownerFirestore(projectId) {
  const credential = await firebaseCLICredential();
  const authClient = new OAuth2Client();
  authClient.refreshHandler = async () => {
    const token = await credential.getAccessToken();
    return { access_token: token.access_token, expiry_date: Date.now() + token.expires_in * 1000 };
  };
  authClient.setCredentials(await authClient.refreshHandler());
  return new Firestore({ projectId, authClient });
}
