import { Router } from 'express';

import { db, FieldValue } from '../lib/firebase.js';
import { checkQuota } from '../lib/quota.js';
import { HttpError, route } from '../lib/http.js';
import { generateJson, geminiSchemas, mock, mockMode, prompts } from '../lib/llm.js';
import {
  errorsText,
  explainOutput,
  explainRequest,
  extractOutput,
  progressOutput,
  progressRequest,
  sanitizeValues,
} from '../lib/schemas.js';

const router = Router();

const incrementUsage = (uid, kind) => db.doc(`users/${uid}`).update({ [`aiUsage.${kind}`]: FieldValue.increment(1) });

// Step 3: image -> strict JSON values.
router.post(
  '/inbody/extract',
  route(async (req, res) => {
    checkQuota(req.profile, 'scans');
    const { imageBase64, mimeType = 'image/jpeg' } = req.body || {};
    if (typeof imageBase64 !== 'string' || imageBase64.length < 1000) throw new HttpError(400, 'Image is missing.');
    if (imageBase64.length > 10 * 1024 * 1024) throw new HttpError(413, 'Image is too large. Please use a smaller photo.');
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) throw new HttpError(400, 'Unsupported image type.');

    const out = mockMode()
      ? mock.extract()
      : await generateJson({
          system: prompts.extract,
          parts: [{ inline_data: { mime_type: mimeType, data: imageBase64 } }, { text: 'Extract the InBody values.' }],
          responseSchema: geminiSchemas.extract,
          temperature: 0,
        });
    if (!extractOutput(out)) {
      console.error('extract schema failed:', errorsText(extractOutput));
      throw new HttpError(502, 'The AI answer was incomplete. Please try again.');
    }
    if (!out.isInBody) throw new HttpError(422, 'This image does not look like an InBody result sheet.');
    const scanDate = /^\d{4}-\d{2}-\d{2}$/.test(out.scanDate || '') ? out.scanDate : null;
    res.json({ values: sanitizeValues(out.values), scanDate });
  }),
);

// Step 5: confirmed values + goal -> explanation.
router.post(
  '/inbody/explain',
  route(async (req, res) => {
    checkQuota(req.profile, 'scans');
    if (!explainRequest(req.body)) throw new HttpError(400, `Invalid values: ${errorsText(explainRequest)}`);
    const { values, goal } = req.body;

    const out = mockMode()
      ? mock.explain(values, goal)
      : await generateJson({
          system: prompts.explain,
          parts: [{ text: JSON.stringify({ goal, sex_and_age: 'unknown', values }) }],
          responseSchema: geminiSchemas.explain,
        });
    if (!explainOutput(out)) {
      console.error('explain schema failed:', errorsText(explainOutput));
      throw new HttpError(502, 'The AI answer was incomplete. Please try again.');
    }
    await incrementUsage(req.uid, 'scans');
    res.json({ summary: out.summary.trim(), nextSteps: out.nextSteps.map((s) => s.trim()) });
  }),
);

// Progress narrative from computed numbers only.
router.post(
  '/inbody/progress',
  route(async (req, res) => {
    checkQuota(req.profile, 'progress');
    if (!progressRequest(req.body)) throw new HttpError(400, `Invalid progress data: ${errorsText(progressRequest)}`);
    const { progress } = req.body;

    const out = mockMode()
      ? mock.progress(progress)
      : await generateJson({
          system: prompts.progress,
          parts: [{ text: JSON.stringify(progress) }],
          responseSchema: geminiSchemas.progress,
        });
    if (!progressOutput(out)) {
      console.error('progress schema failed:', errorsText(progressOutput));
      throw new HttpError(502, 'The AI answer was incomplete. Please try again.');
    }
    await incrementUsage(req.uid, 'progress');
    res.json({ narrative: out.narrative.trim(), focus: out.focus.map((s) => s.trim()) });
  }),
);

export default router;
