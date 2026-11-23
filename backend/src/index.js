import 'dotenv/config';

import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';

import { errorHandler } from './lib/http.js';
import { mockMode } from './lib/llm.js';
import { requireAuth } from './middleware/auth.js';
import aiRoutes from './routes/ai.js';
import fileRoutes, { UPLOAD_DIR } from './routes/files.js';
import notifyRoutes from './routes/notify.js';
import writeRoutes from './routes/writes.js';

const app = express();
app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '12mb' }));

app.get('/health', (_req, res) => res.json({ ok: true, mockAI: mockMode() }));

// Uploaded images (public but unguessable URLs, like Firebase download URLs).
const serveFiles = express.static(UPLOAD_DIR, { maxAge: '7d', fallthrough: false, dotfiles: 'deny' });
app.use('/files', (req, res, next) => (req.method === 'GET' || req.method === 'HEAD' ? serveFiles(req, res, next) : next()));

// Everything below needs a verified Firebase ID token.
app.use(requireAuth);

const perUser = (max) =>
  rateLimit({
    windowMs: 60_000,
    max,
    keyGenerator: (req) => req.uid,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests. Please wait a minute and try again.' },
  });

app.use('/ai', perUser(Number(process.env.AI_RATE_LIMIT_PER_MIN || 10)), aiRoutes);
app.use('/notify', perUser(60), notifyRoutes);
app.use('/files', perUser(30), fileRoutes);
app.use('/', perUser(20), writeRoutes);

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));
app.use(errorHandler);

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`FitLink backend listening on http://localhost:${port} (mock AI: ${mockMode()})`);
});
