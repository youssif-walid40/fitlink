import { Router } from 'express';

import { db, FieldValue, messaging } from '../lib/firebase.js';
import { HttpError, route } from '../lib/http.js';

const router = Router();

/**
 * Sends a push to every device of a user and prunes dead tokens.
 * data.route tells the app which screen to open when tapped.
 */
export async function sendToUser(uid, { title, body, data = {} }) {
  const snap = await db.doc(`users/${uid}`).get();
  const tokens = (snap.data()?.fcmTokens || []).filter(Boolean);
  if (!tokens.length) return { sent: 0 };

  const stringData = Object.fromEntries(Object.entries({ ...data, title, body }).map(([k, v]) => [k, String(v ?? '')]));
  const result = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: stringData,
    android: { priority: 'high', notification: { sound: 'default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  });

  const dead = result.responses
    .map((r, i) => (!r.success && /registration-token-not-registered|invalid-registration-token|invalid-argument/.test(r.error?.code || '') ? tokens[i] : null))
    .filter(Boolean);
  if (dead.length) await db.doc(`users/${uid}`).update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  return { sent: result.successCount };
}

export function coachingMessage(c, actorUid) {
  const title = c.proposal?.title || 'your plan';
  const byPt = actorUid === c.ptId;
  switch (c.status) {
    case 'requested':
      return { title: 'New coaching request', body: `${c.memberName} wants to train with you.` };
    case 'accepted':
      return { title: 'Request accepted', body: `${c.ptName} accepted your request. A plan proposal is coming.` };
    case 'declined':
      return { title: 'Request declined', body: `${c.ptName} can't take you on right now.` };
    case 'proposed':
      return { title: 'New plan proposal', body: `${c.ptName} sent you "${title}". Review and accept or counter.` };
    case 'countered':
      return { title: 'Counter offer', body: `${c.memberName} suggested changes to "${title}".` };
    case 'active':
      return byPt
        ? { title: 'Plan is active 💪', body: `${c.ptName} accepted your changes. "${title}" starts now.` }
        : { title: 'Plan accepted 🎉', body: `${c.memberName} accepted "${title}".` };
    case 'completed':
      return { title: 'Coaching completed', body: `${c.ptName} marked your coaching as completed. Leave a review!` };
    case 'cancelled':
      return { title: 'Request cancelled', body: `${c.memberName} cancelled the coaching request.` };
    default:
      return { title: 'Coaching update', body: `Your coaching with ${byPt ? c.memberName : c.ptName} was updated.` };
  }
}

/**
 * POST /notify { type: 'coaching' | 'session' | 'chat', refId, preview? }
 * The backend decides who receives the push (the *other* participant) and
 * verifies that the caller is a participant – so nobody can spam strangers.
 */
router.post(
  '/',
  route(async (req, res) => {
    const { type, refId, preview } = req.body || {};
    if (typeof refId !== 'string' || !refId || refId.includes('/')) throw new HttpError(400, 'Invalid reference.');

    if (type === 'chat') {
      const snap = await db.doc(`chats/${refId}`).get();
      const chat = snap.data();
      if (!chat || !chat.participants?.includes(req.uid)) throw new HttpError(403, 'Not a participant.');
      const to = chat.participants.find((p) => p !== req.uid);
      const from = chat.names?.[req.uid] || req.profile.name || 'New message';
      const body = String(preview || chat.lastMessage || 'New message').slice(0, 140);
      const r = await sendToUser(to, { title: from, body, data: { type: 'chat', chatId: refId, route: `/chat/${refId}` } });
      return res.json(r);
    }

    if (type === 'coaching' || type === 'session') {
      const snap = await db.doc(`coachings/${refId}`).get();
      const c = snap.data();
      if (!c || !c.participants?.includes(req.uid)) throw new HttpError(403, 'Not a participant.');
      const to = req.uid === c.memberId ? c.ptId : c.memberId;
      const msg =
        type === 'session'
          ? {
              title: 'Session logged',
              body: `${c.memberName} completed a workout (${c.sessionsDone}/${(c.proposal?.durationWeeks || 0) * (c.proposal?.sessionsPerWeek || 0)}).`,
            }
          : coachingMessage(c, req.uid);
      const r = await sendToUser(to, { ...msg, data: { type, coachingId: refId, route: `/coaching/${refId}` } });
      return res.json(r);
    }

    throw new HttpError(400, 'Unknown notification type.');
  }),
);

export default router;
