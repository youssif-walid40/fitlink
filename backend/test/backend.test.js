import assert from 'node:assert/strict';
import { test } from 'node:test';

import { mock } from '../src/lib/llm.js';
import { checkQuota, isPremiumActive } from '../src/lib/quota.js';
import { explainOutput, explainRequest, extractOutput, progressOutput, progressRequest, sanitizeValues } from '../src/lib/schemas.js';

const member = (extra = {}) => ({ role: 'member', aiUsage: { scans: 0, progress: 0 }, ...extra });
const limits = { scans: 2, progress: 1 };

test('free member within quota passes', () => {
  assert.doesNotThrow(() => checkQuota(member({ aiUsage: { scans: 1, progress: 0 } }), 'scans', limits));
});

test('free member over quota gets 402', () => {
  assert.throws(() => checkQuota(member({ aiUsage: { scans: 2, progress: 0 } }), 'scans', limits), (e) => e.status === 402);
  assert.throws(() => checkQuota(member({ aiUsage: { scans: 0, progress: 1 } }), 'progress', limits), (e) => e.status === 402);
});

test('premium member is unlimited until expiry', () => {
  const future = new Date(Date.now() + 86_400_000);
  const past = new Date(Date.now() - 86_400_000);
  assert.equal(isPremiumActive({ isPremium: true, premiumUntil: future }), true);
  assert.equal(isPremiumActive({ isPremium: true, premiumUntil: past }), false);
  assert.doesNotThrow(() => checkQuota(member({ isPremium: true, premiumUntil: future, aiUsage: { scans: 99 } }), 'scans', limits));
});

test('non-members cannot use InBody AI', () => {
  assert.throws(() => checkQuota({ role: 'pt' }, 'scans', limits), (e) => e.status === 403);
});

test('sanitizeValues nulls out-of-range misreads', () => {
  const v = sanitizeValues({ weight: 82.456, percentBodyFat: 240, bmi: 'x', totalBodyWater: 38.4 });
  assert.equal(v.weight, 82.46);
  assert.equal(v.percentBodyFat, null);
  assert.equal(v.bmi, null);
  assert.equal(v.totalBodyWater, 38.4);
  assert.equal(v.visceralFatLevel, null);
});

test('mock outputs satisfy the LLM output schemas', () => {
  assert.ok(extractOutput(mock.extract()));
  const values = mock.extract().values;
  assert.ok(explainOutput(mock.explain(values, 'fat_loss')));
  const progress = {
    goal: 'fat_loss',
    weeks: 8,
    scanCount: 2,
    metrics: [{ metric: 'weight', label: 'Weight', first: 85, last: 82, change: -3, perWeek: -0.38, trend: 'down', assessment: 'improved' }],
  };
  assert.ok(progressRequest({ progress }));
  assert.ok(progressOutput(mock.progress(progress)));
});

test('explain request requires core values within range', () => {
  assert.equal(explainRequest({ goal: 'fat_loss', values: { weight: 80 } }), false);
  assert.equal(explainRequest({ goal: 'fat_loss', values: { weight: 80, percentBodyFat: 20, skeletalMuscleMass: 30 } }), true);
  assert.equal(explainRequest({ goal: 'bulk', values: { weight: 80, percentBodyFat: 20, skeletalMuscleMass: 30 } }), false);
  assert.equal(explainRequest({ goal: 'fat_loss', values: { weight: 900, percentBodyFat: 20, skeletalMuscleMass: 30 } }), false);
});
