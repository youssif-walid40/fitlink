import { auth, db } from '../lib/firebase.js';
import { HttpError } from '../lib/http.js';

/**
 * Every endpoint requires a valid Firebase ID token:
 *   Authorization: Bearer <idToken>
 * Sets req.uid and req.profile (the users/{uid} document).
 */
export async function requireAuth(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new HttpError(401, 'Missing sign-in token.');
    const decoded = await auth.verifyIdToken(token);
    req.uid = decoded.uid;
    const snap = await db.doc(`users/${decoded.uid}`).get();
    req.profile = snap.exists ? snap.data() : null;
    if (!req.profile) throw new HttpError(403, 'User profile not found.');
    next();
  } catch (e) {
    next(e instanceof HttpError ? e : new HttpError(401, 'Your session has expired. Please sign in again.'));
  }
}
