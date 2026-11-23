import { readFileSync } from 'node:fs';
import { initializeApp, applicationDefault, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

function credential() {
  const path = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (path) {
    try {
      return cert(JSON.parse(readFileSync(path, 'utf8')));
    } catch (e) {
      console.warn(`Could not read service account at ${path}: ${e.message}. Falling back to application default credentials.`);
    }
  }
  return applicationDefault();
}

if (!getApps().length) initializeApp({ credential: credential() });

export const auth = getAuth();
export const db = getFirestore();
export const messaging = getMessaging();
export { FieldValue, Timestamp };
