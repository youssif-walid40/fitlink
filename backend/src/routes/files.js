import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { Router } from 'express';

import { db } from '../lib/firebase.js';
import { HttpError, route } from '../lib/http.js';

/**
 * Media storage backend (replaces Firebase Storage so the project can stay on
 * the free Spark plan).
 *
 *  POST /files/upload { path, imageBase64 }  -> { url: "/files/<stored path>" }
 *  GET  /files/<stored path>                  (served statically, see index.js)
 *
 * Write access mirrors the old storage.rules:
 *   users/{uid}/avatar.jpg        – only that user
 *   users/{uid}/scans/{id}.jpg    – only that user
 *   pts/{uid}/{file}.jpg          – only that trainer
 *   gyms/{gymId}/{file}.jpg       – only the gym's owner (checked in Firestore)
 *   chats/{chatId}/{file}.jpg     – only the two chat participants
 *
 * Every stored file name gets a random 128-bit token, so URLs cannot be
 * guessed. This is the same model Firebase Storage download URLs use.
 */
export const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || './uploads');
const MAX_BYTES = 8 * 1024 * 1024;
const SEGMENT = /^[A-Za-z0-9_-]{1,128}$/;
const FILE = /^[A-Za-z0-9_-]{1,100}\.(jpg|jpeg|png|webp)$/;

async function canWrite(uid, parts) {
  const [root, id] = parts;
  if (root === 'users') {
    if (id !== uid) return false;
    return (parts.length === 3 && parts[2] === 'avatar.jpg') || (parts.length === 4 && parts[2] === 'scans');
  }
  if (parts.length !== 3) return false;
  if (root === 'pts') return id === uid;
  if (root === 'gyms') return (await db.doc(`gyms/${id}`).get()).data()?.ownerId === uid;
  if (root === 'chats') return ((await db.doc(`chats/${id}`).get()).data()?.participants || []).includes(uid);
  return false;
}

const router = Router();

router.post(
  '/upload',
  route(async (req, res) => {
    const { path: wanted, imageBase64 } = req.body || {};
    if (typeof wanted !== 'string' || typeof imageBase64 !== 'string') throw new HttpError(400, 'Missing file.');

    const parts = wanted.split('/');
    const file = parts[parts.length - 1];
    if (!FILE.test(file) || !parts.slice(0, -1).every((p) => SEGMENT.test(p))) {
      throw new HttpError(400, 'Invalid file path.');
    }
    if (!(await canWrite(req.uid, parts))) throw new HttpError(403, 'You cannot upload here.');

    const bytes = Buffer.from(imageBase64, 'base64');
    if (bytes.length === 0 || bytes.length > MAX_BYTES) throw new HttpError(413, 'Image must be smaller than 8 MB.');
    const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
    const isPng = bytes[0] === 0x89 && bytes[1] === 0x50;
    const isWebp = bytes.subarray(8, 12).toString() === 'WEBP';
    if (!isJpeg && !isPng && !isWebp) throw new HttpError(415, 'Only JPEG, PNG or WebP images are allowed.');

    const dot = file.lastIndexOf('.');
    const storedName = `${file.slice(0, dot)}-${randomBytes(16).toString('hex')}${file.slice(dot)}`;
    const relative = [...parts.slice(0, -1), storedName].join('/');
    const target = path.join(UPLOAD_DIR, ...relative.split('/'));
    if (!target.startsWith(UPLOAD_DIR + path.sep)) throw new HttpError(400, 'Invalid file path.');

    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, bytes);
    // Relative URL: the app prefixes its own BACKEND_URL, so the same data works
    // on an emulator (10.0.2.2) and on a phone (LAN IP).
    res.json({ url: `/files/${relative}` });
  }),
);

export default router;
