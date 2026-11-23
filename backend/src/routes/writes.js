import { Router } from 'express';

import { db, FieldValue, Timestamp } from '../lib/firebase.js';
import { HttpError, route } from '../lib/http.js';
import { sendToUser } from './notify.js';

/**
 * Sensitive writes the app is not allowed to make directly (locked by
 * firestore.rules): premium upgrades, sponsored placement and verified reviews.
 */
const router = Router();

const PLANS = { monthly: { days: 30, price: 99 }, yearly: { days: 365, price: 899 } };
const SPONSOR = { 7: 500, 30: 1500 };
const addDays = (d, n) => new Date(d.getTime() + n * 24 * 60 * 60 * 1000);

// POST /premium/activate { plan }
router.post(
  '/premium/activate',
  route(async (req, res) => {
    const plan = PLANS[req.body?.plan];
    if (!plan) throw new HttpError(400, 'Unknown plan.');
    const ref = db.doc(`users/${req.uid}`);
    const premiumUntil = await db.runTransaction(async (tx) => {
      const u = (await tx.get(ref)).data();
      const current = u?.premiumUntil?.toDate?.();
      const start = current && current > new Date() ? current : new Date();
      const until = addDays(start, plan.days);
      tx.update(ref, { isPremium: true, premiumUntil: Timestamp.fromDate(until), premiumPlan: req.body.plan });
      tx.set(db.collection('payments').doc(), {
        uid: req.uid,
        kind: 'premium',
        plan: req.body.plan,
        amountEgp: plan.price,
        simulated: true,
        createdAt: FieldValue.serverTimestamp(),
      });
      return until;
    });
    res.json({ ok: true, premiumUntil: premiumUntil.toISOString() });
  }),
);

// POST /gyms/sponsor { gymId, days }
router.post(
  '/gyms/sponsor',
  route(async (req, res) => {
    const { gymId, days } = req.body || {};
    const price = SPONSOR[days];
    if (!price || typeof gymId !== 'string' || gymId.includes('/')) throw new HttpError(400, 'Invalid sponsorship request.');
    const ref = db.doc(`gyms/${gymId}`);
    const until = await db.runTransaction(async (tx) => {
      const g = (await tx.get(ref)).data();
      if (!g) throw new HttpError(404, 'Gym not found.');
      if (g.ownerId !== req.uid) throw new HttpError(403, 'Only the gym owner can sponsor this listing.');
      if (!g.verified) throw new HttpError(409, 'Your gym must be verified before it can be sponsored.');
      const current = g.sponsoredUntil?.toDate?.();
      const start = current && current > new Date() ? current : new Date();
      const end = addDays(start, days);
      tx.update(ref, { sponsored: true, sponsoredUntil: Timestamp.fromDate(end) });
      tx.set(db.collection('payments').doc(), {
        uid: req.uid,
        kind: 'sponsor',
        gymId,
        days,
        amountEgp: price,
        simulated: true,
        createdAt: FieldValue.serverTimestamp(),
      });
      return end;
    });
    res.json({ ok: true, sponsoredUntil: until.toISOString() });
  }),
);

// POST /reviews { coachingId, rating, comment }
router.post(
  '/reviews',
  route(async (req, res) => {
    const { coachingId, rating, comment } = req.body || {};
    if (typeof coachingId !== 'string' || coachingId.includes('/')) throw new HttpError(400, 'Invalid coaching.');
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw new HttpError(400, 'Rating must be 1–5.');
    if (typeof comment !== 'string' || comment.trim().length < 10 || comment.length > 600) {
      throw new HttpError(400, 'Comment must be 10–600 characters.');
    }

    const cRef = db.doc(`coachings/${coachingId}`);
    const ptId = await db.runTransaction(async (tx) => {
      const c = (await tx.get(cRef)).data();
      if (!c) throw new HttpError(404, 'Coaching not found.');
      if (c.memberId !== req.uid) throw new HttpError(403, 'Only the client can review this coaching.');
      if (c.status !== 'completed') throw new HttpError(409, 'You can review only after the coaching is completed.');
      if (c.reviewed) throw new HttpError(409, 'You already reviewed this coaching.');

      const ptRef = db.doc(`pts/${c.ptId}`);
      const pt = (await tx.get(ptRef)).data() || {};
      const count = pt.reviewCount || 0;
      const avg = pt.rating || 0;
      const newCount = count + 1;
      const newAvg = Math.round(((avg * count + rating) / newCount) * 100) / 100;

      tx.set(ptRef.collection('reviews').doc(coachingId), {
        memberId: req.uid,
        memberName: c.memberName,
        rating,
        comment: comment.trim(),
        coachingId,
        verified: true,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.update(ptRef, { rating: newAvg, reviewCount: newCount });
      tx.update(cRef, {
        reviewed: true,
        updatedAt: FieldValue.serverTimestamp(),
        events: FieldValue.arrayUnion({ status: 'reviewed', by: req.uid, note: `${rating}★`, at: Timestamp.now() }),
      });
      return c.ptId;
    });

    sendToUser(ptId, {
      title: 'New review ⭐',
      body: `${req.profile.name} rated you ${rating}/5.`,
      data: { type: 'review', route: `/trainers/${ptId}` },
    }).catch((e) => console.warn('review push failed', e.message));
    res.json({ ok: true });
  }),
);

export default router;
