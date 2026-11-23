import { HttpError } from './http.js';

const FREE = () => ({
  scans: Number(process.env.FREE_SCAN_QUOTA ?? 2),
  progress: Number(process.env.FREE_PROGRESS_QUOTA ?? 1),
});

export function isPremiumActive(profile, now = new Date()) {
  if (!profile?.isPremium) return false;
  const until = profile.premiumUntil?.toDate?.() ?? (profile.premiumUntil ? new Date(profile.premiumUntil) : null);
  return !until || until > now;
}

/** Premium status and quota are checked server-side – never trusted from the app. */
export function checkQuota(profile, kind, limits = FREE()) {
  if (profile?.role !== 'member') throw new HttpError(403, 'InBody analysis is available to member accounts.');
  if (isPremiumActive(profile)) return;
  const used = profile?.aiUsage?.[kind] ?? 0;
  if (used >= limits[kind]) {
    const what = kind === 'scans' ? `${limits.scans} free InBody analyses` : `${limits.progress} free progress analysis`;
    throw new HttpError(402, `You have used your ${what}. Upgrade to Premium for unlimited analysis.`, 'quota_exceeded');
  }
}

