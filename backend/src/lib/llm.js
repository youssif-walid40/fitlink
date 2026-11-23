import { HttpError } from './http.js';

const MODEL = () => process.env.GEMINI_MODEL || 'gemini-2.5-flash';
export const mockMode = () => String(process.env.MOCK_AI).toLowerCase() === 'true';

/**
 * Calls Gemini and returns parsed JSON. The response is constrained with
 * responseMimeType=application/json + responseSchema, then validated again by
 * the caller with AJV – the model is never trusted blindly.
 */
export async function generateJson({ system, parts, responseSchema, temperature = 0.3 }) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new HttpError(503, 'AI is not configured on the server (missing GEMINI_API_KEY).');

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL()}:generateContent`;
  const body = {
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: 'user', parts }],
    generationConfig: { temperature, responseMimeType: 'application/json', responseSchema },
  };

  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60_000),
    });
  } catch (e) {
    throw new HttpError(504, 'The AI service did not respond in time. Please try again.');
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    console.error('Gemini error', res.status, text.slice(0, 500));
    if (res.status === 429) throw new HttpError(429, 'The AI service is busy. Please try again in a minute.');
    throw new HttpError(502, 'The AI service returned an error. Please try again.');
  }
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') ?? '';
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(502, 'The AI returned an unreadable answer. Please try again.');
  }
}

// Gemini response schemas (OpenAPI subset).
const NUM = { type: 'NUMBER', nullable: true };
export const geminiSchemas = {
  extract: {
    type: 'OBJECT',
    properties: {
      isInBody: { type: 'BOOLEAN' },
      scanDate: { type: 'STRING', nullable: true, description: 'YYYY-MM-DD if printed on the sheet' },
      values: {
        type: 'OBJECT',
        properties: {
          weight: NUM,
          skeletalMuscleMass: NUM,
          bodyFatMass: NUM,
          percentBodyFat: NUM,
          bmi: NUM,
          basalMetabolicRate: NUM,
          visceralFatLevel: NUM,
          totalBodyWater: NUM,
        },
        required: [
          'weight',
          'skeletalMuscleMass',
          'bodyFatMass',
          'percentBodyFat',
          'bmi',
          'basalMetabolicRate',
          'visceralFatLevel',
          'totalBodyWater',
        ],
      },
    },
    required: ['isInBody', 'values'],
  },
  explain: {
    type: 'OBJECT',
    properties: {
      summary: { type: 'STRING' },
      nextSteps: { type: 'ARRAY', items: { type: 'STRING' } },
    },
    required: ['summary', 'nextSteps'],
  },
  progress: {
    type: 'OBJECT',
    properties: {
      narrative: { type: 'STRING' },
      focus: { type: 'ARRAY', items: { type: 'STRING' } },
    },
    required: ['narrative', 'focus'],
  },
};

export const prompts = {
  extract: `You read InBody body-composition result sheets (printouts or screenshots).
Return ONLY numbers that are clearly printed on the sheet. Never guess or calculate a value.
Use null for any value that is missing, cut off or unreadable.
Units: weight, skeletalMuscleMass, bodyFatMass in kg; percentBodyFat in %; basalMetabolicRate in kcal; totalBodyWater in L (litres); visceralFatLevel is a level number; bmi has no unit.
If the sheet shows pounds, convert to kg (1 lb = 0.4536 kg).
scanDate: the test date printed on the sheet as YYYY-MM-DD, or null.
Set isInBody=false and all values null if the image is not a body-composition result.`,

  explain: `You are a friendly, evidence-based fitness coach writing for a gym member in Egypt.
Explain InBody results in plain, encouraging language a beginner understands.
Rules:
- 3 to 5 sentences in "summary". Mention the most important numbers and what they mean in context of the member's goal.
- 3 to 5 short, practical "nextSteps" (training, protein, calories, water, sleep). Use metric units.
- This is general fitness guidance, NOT medical advice. Never diagnose a disease or prescribe medication.
- If a value looks unusual (e.g. very high visceral fat), gently suggest checking with a doctor.
- No markdown, no emojis.`,

  progress: `You are a fitness coach reviewing a member's InBody progress.
You receive ONLY pre-computed numbers (first value, last value, change, change per week, trend, and whether that trend is good for the goal).
Do NOT recalculate or invent numbers – quote the ones you are given.
Write "narrative": 3 to 5 sentences covering what improved, what stalled or went the wrong way, and the overall direction for the goal.
Write "focus": 2 to 4 short, specific things to focus on next.
General fitness guidance only, not medical advice. No markdown, no emojis.`,
};

// ---------- Mock answers (MOCK_AI=true) ----------

export const mock = {
  extract: () => ({
    isInBody: true,
    scanDate: new Date().toISOString().slice(0, 10),
    values: {
      weight: 82.4,
      skeletalMuscleMass: 31.2,
      bodyFatMass: 20.3,
      percentBodyFat: 24.6,
      bmi: 26.1,
      basalMetabolicRate: 1720,
      visceralFatLevel: 9,
      totalBodyWater: 38.4,
    },
  }),
  explain: (values, goal) => ({
    summary:
      `Your body fat is ${values.percentBodyFat}%, which is slightly above the typical range for most adults, ` +
      `while your muscle mass of ${values.skeletalMuscleMass} kg is a solid base to build on. ` +
      (goal === 'muscle_gain'
        ? 'A small calorie surplus with progressive strength training will help you add lean muscle.'
        : 'A small calorie deficit with regular strength training will improve your ratio over the next 8 weeks.'),
    nextSteps: [
      `Aim for about ${Math.round((values.weight || 80) * 1.6)} g of protein per day`,
      'Lift 3 to 4 times a week and add two short cardio sessions',
      'Drink at least 2.5 L of water daily and sleep 7 to 8 hours',
    ],
  }),
  progress: (p) => {
    const improved = p.metrics.filter((m) => m.assessment === 'improved').map((m) => m.label || m.metric);
    const worse = p.metrics.filter((m) => m.assessment === 'worsened').map((m) => m.label || m.metric);
    return {
      narrative:
        `Over ${p.weeks} weeks and ${p.scanCount} scans you have made real progress. ` +
        (improved.length ? `${improved.join(', ')} moved in the right direction for your goal. ` : '') +
        (worse.length ? `${worse.join(', ')} need more attention. ` : 'Nothing went the wrong way. ') +
        'Keep training consistently and re-scan in 4 weeks to confirm the trend.',
      focus: ['Keep protein high on training days', 'Add one extra strength session per week', 'Track sleep and water daily'],
    };
  },
};
