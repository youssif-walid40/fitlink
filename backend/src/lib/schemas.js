import Ajv from 'ajv';

const ajv = new Ajv({ allErrors: true, coerceTypes: false });

/** Valid ranges – mirrors kMetrics in lib/models/scan.dart. */
export const METRICS = {
  weight: [20, 300],
  skeletalMuscleMass: [5, 80],
  bodyFatMass: [1, 150],
  percentBodyFat: [2, 70],
  bmi: [10, 70],
  basalMetabolicRate: [500, 4000],
  visceralFatLevel: [1, 30],
  totalBodyWater: [10, 80],
};
export const GOALS = ['fat_loss', 'muscle_gain', 'maintenance'];

const nullableNumber = { type: ['number', 'null'] };

// ---------- LLM output schemas (validated after every call) ----------

export const extractOutput = ajv.compile({
  type: 'object',
  required: ['isInBody', 'values'],
  properties: {
    isInBody: { type: 'boolean' },
    scanDate: { type: ['string', 'null'] },
    values: {
      type: 'object',
      required: Object.keys(METRICS),
      properties: Object.fromEntries(Object.keys(METRICS).map((k) => [k, nullableNumber])),
    },
  },
});

export const explainOutput = ajv.compile({
  type: 'object',
  required: ['summary', 'nextSteps'],
  properties: {
    summary: { type: 'string', minLength: 20, maxLength: 1200 },
    nextSteps: { type: 'array', minItems: 2, maxItems: 6, items: { type: 'string', minLength: 5, maxLength: 300 } },
  },
});

export const progressOutput = ajv.compile({
  type: 'object',
  required: ['narrative', 'focus'],
  properties: {
    narrative: { type: 'string', minLength: 20, maxLength: 1500 },
    focus: { type: 'array', minItems: 1, maxItems: 5, items: { type: 'string', minLength: 3, maxLength: 300 } },
  },
});

// ---------- Request body schemas ----------

export const explainRequest = ajv.compile({
  type: 'object',
  required: ['values', 'goal'],
  properties: {
    goal: { enum: GOALS },
    values: {
      type: 'object',
      required: ['weight', 'percentBodyFat', 'skeletalMuscleMass'],
      additionalProperties: false,
      properties: Object.fromEntries(
        Object.entries(METRICS).map(([k, [min, max]]) => [k, { type: 'number', minimum: min, maximum: max }]),
      ),
    },
  },
});

export const progressRequest = ajv.compile({
  type: 'object',
  required: ['progress'],
  properties: {
    progress: {
      type: 'object',
      required: ['goal', 'weeks', 'scanCount', 'metrics'],
      properties: {
        goal: { enum: GOALS },
        from: { type: 'string' },
        to: { type: 'string' },
        weeks: { type: 'number', minimum: 0, maximum: 520 },
        scanCount: { type: 'integer', minimum: 2, maximum: 500 },
        metrics: {
          type: 'array',
          minItems: 1,
          maxItems: 8,
          items: {
            type: 'object',
            required: ['metric', 'first', 'last', 'change', 'trend', 'assessment'],
            properties: {
              metric: { enum: Object.keys(METRICS) },
              label: { type: 'string', maxLength: 60 },
              unit: { type: 'string', maxLength: 10 },
              first: { type: 'number' },
              last: { type: 'number' },
              change: { type: 'number' },
              percentChange: { type: ['number', 'null'] },
              perWeek: { type: 'number' },
              trend: { enum: ['up', 'down', 'flat'] },
              assessment: { enum: ['improved', 'worsened', 'stable'] },
            },
          },
        },
      },
    },
  },
});

export function errorsText(validate) {
  return ajv.errorsText(validate.errors, { separator: '; ' });
}

/** Drops values outside physiological ranges (an LLM misread) to null. */
export function sanitizeValues(values) {
  const out = {};
  for (const [k, [min, max]] of Object.entries(METRICS)) {
    const v = values?.[k];
    out[k] = typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max ? Math.round(v * 100) / 100 : null;
  }
  return out;
}
