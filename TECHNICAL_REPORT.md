# FitLink – Technical Report (draft)

CSEN1114 Mobile Application Development · Winter 2026 · Group FitLink

> Draft generated with the code. Edit the wording, add screenshots and adjust anything you changed.

## 1. Architecture

```
Flutter app ──(Firebase SDKs)──> Auth · Firestore · FCM
     │
     └──(HTTPS + Firebase ID token)──> Node.js REST backend ──> Gemini (LLM)
                                              │
                                              ├──(Admin SDK)──> Firestore · FCM
                                              └── media store (backend/uploads, served at /files/*)
```

**Client layers**

| Layer | Responsibility |
|---|---|
| `screens/` | UI only. Reads state with `context.watch` / `Consumer`. |
| `providers/` | App state as `ChangeNotifier`: session, theme, gym and trainer filters, scan history. |
| `StreamProvider`s | Live Firestore data wrapped in `LiveData<T>` (loading / data / error), so every screen handles states the same way. |
| `repositories/` | One class per feature that talks to Firestore. |
| `services/` | Platform and external integrations: auth, storage, REST API, FCM, GPS, ML Kit OCR, local cache. |
| `logic/` | Pure Dart business rules (coaching state machine, progress maths), fully unit-tested. |

**Navigation** uses `go_router` with a single `redirect` that protects all routes:
signed-out users go to `/login`, and role-specific prefixes (`/owner`, `/admin`, `/inbody`, `/pt`, `/propose`, `/counter`, `/review`) send other roles back to `/home`.
Routes carry path parameters (`/coaching/:id`, `/chat/:chatId`, `/scan/:memberId/:scanId`).
Notification taps push the same routes, and `goBack()` falls back to `/home` when a screen was opened directly from a push.

**Backend** (Express, firebase-admin) exists for three reasons:
1. keep the LLM API key off the device;
2. send pushes to *another* user (clients cannot hold FCM server credentials);
3. perform writes that must not be trusted to the client: premium upgrades, sponsored placement, verified reviews and rating aggregates;
4. store media. Images are uploaded to `POST /files/upload`, which checks the same ownership rules Firebase Storage rules would, and are served from `/files/*`. This keeps the project on Firebase's free Spark plan.

## 2. Data model (Cloud Firestore)

| Collection | Key fields | Who writes |
|---|---|---|
| `users/{uid}` | name, email, role, goal, gymId/gymName/gymTier, photoUrl, fcmTokens, isPremium, premiumUntil, aiUsage{scans,progress} | Owner (limited fields), backend (role-locked fields) |
| `users/{uid}/scans/{id}` | values{8 metrics}, scanDate, goal, summary, nextSteps[], imageUrl, sharedWith[] | Owner |
| `users/{uid}/progressReports/{id}` | narrative, focus[], fromScanId, toScanId, numbers | Owner |
| `pts/{uid}` | name, bio, specialties[], monthlyPrice, mode, yearsExperience, transformations[], rating, reviewCount, verified | PT (profile), admin (verified), backend (rating) |
| `pts/{uid}/reviews/{coachingId}` | memberName, rating, comment | Backend only (one per completed coaching) |
| `gyms/{id}` | ownerId, name, area, lat/lng, tiers[], facilities[], policies[], photos[], openHours, verified, sponsored, sponsoredUntil | Owner, admin (verified), backend (sponsored) |
| `gyms/{id}/members/{uid}` | name, tier, joinedAt | The member |
| `affiliations/{ptId_gymId}` | ptId, gymId, ownerId, status (pending/approved/rejected) | PT creates, gym owner decides |
| `coachings/{id}` | memberId, ptId, participants[], status, proposal{…}, counter{…}, events[], sessionsDone, sharedScanIds[], reviewed | Both participants, within the state machine |
| `chats/{a_b}` + `messages/{id}` | participants[], names, lastMessage · senderId, type (text/image/scan/proposal), payload | Participants |
| `reports/{id}`, `payments/{id}` | moderation queue · simulated payment log | Any user / backend |

Names and photos are copied into `coachings` and `chats` so lists render without extra reads. Chat ids are the two sorted uids joined with `_`, so each pair of users has exactly one thread.

## 3. The two-user workflow: hiring a PT

`requested → accepted → proposed ⇄ countered → active → completed → reviewed`
(plus `declined` and `cancelled`).

* The transition table lives in `logic/coaching_flow.dart` and is **duplicated in `firestore.rules`** (`validTransition`), so a modified client still cannot skip a step or act as the other role.
* Every transition runs in a Firestore transaction that re-reads the current status, which prevents races when both users act at once.
* Both users watch the same document through a `StreamProvider`, so each screen updates the moment the other user acts.
* After each action the client calls `POST /notify`. The backend checks the caller is a participant, then pushes to the *other* user with `data.route=/coaching/{id}`.
* Reviews go through `POST /reviews`, which checks `status == completed && !reviewed`, writes the review with the coaching id as its document id (one review per coaching), and updates the PT's average rating, all in one transaction.

## 4. API integrations

| Endpoint | Purpose |
|---|---|
| `POST /ai/inbody/extract` | Image (base64) → strict JSON of 8 metrics + scan date |
| `POST /ai/inbody/explain` | Confirmed values + goal → summary + next steps |
| `POST /ai/inbody/progress` | Pre-computed deltas → narrative + focus points |
| `POST /notify` | Event-driven FCM push to the other participant |
| `POST /premium/activate` | Simulated subscription → `isPremium`, `premiumUntil` |
| `POST /gyms/sponsor` | Simulated sponsored placement (7 or 30 days) |
| `POST /reviews` | Verified review + rating aggregate |
| `POST /files/upload`, `GET /files/*` | Image storage (avatars, InBody sheets, gym/PT photos, chat images) |
| External | Gemini `generateContent`; OpenStreetMap tiles via `flutter_map` |

All endpoints require a verified Firebase ID token. AI routes are rate-limited per user (default 10 per minute).

## 5. AI design

1. **On-device gate (ML Kit text recognition).** Before any paid call, the photo must contain readable text and at least two InBody keywords. Blurry or wrong photos are rejected instantly and at no cost.
2. **Extraction (multimodal LLM).** Gemini returns JSON constrained by `responseSchema`; the backend re-validates it with AJV and nulls any value outside physiological ranges.
3. **Human in the loop.** The member confirms or corrects every value in a range-validated form before anything is saved.
4. **Explanation.** Only the confirmed numbers and the goal are sent. The prompt forbids diagnosis, and the app always shows a "not medical advice" disclaimer.
5. **Progress.** `ProgressCalculator` (pure Dart, unit-tested) computes change, % change, per-week rate, trend and goal-aware assessment. The LLM receives only these numbers and writes the narrative, so it cannot get the maths wrong.
6. **Monetisation gate.** Free accounts get 2 analyses and 1 progress report. Quota and premium status are checked **server-side** and answered with HTTP 402, which the app turns into an upgrade prompt.

## 6. Key decisions

| Decision | Why |
|---|---|
| Provider + `LiveData<T>` wrapper | Meets the Provider/StreamProvider requirement while giving one consistent loading/error/empty pattern. |
| Live streams above the Navigator (`SignedInScope`) | Screens opened from notifications can still read coaching, chat and gym data. Streams are keyed by uid, so they reset on account switch. |
| State machine in Dart **and** in security rules | Gives fast UI feedback and also enforcement a client cannot bypass. |
| Backend-only sensitive writes | Premium, sponsorship and ratings cannot be forged from a modified app. |
| Hive for lists, SharedPreferences for settings/drafts | Instant start-up and offline browsing; unsent chat messages and proposals survive app restarts. |
| Backend media store instead of Firebase Storage | Firebase Storage now requires the paid Blaze plan; the requirement allows "any other storage backend". Firestore stores relative paths (`/files/…`), so the same data works on emulators and phones. |
| OpenStreetMap instead of Google Maps | No API key or billing needed for maps. |
| Mock AI mode | Demos and grading work even without an LLM key or network. |

## 7. Testing

* `test/progress_calculator_test.dart` – deltas, rates, goal-dependent assessment, thresholds, missing metrics, same-day scans.
* `test/coaching_flow_test.dart` – allowed and forbidden transitions, role separation, review eligibility.
* `test/validators_and_ocr_test.dart` – form validators and the OCR pre-check.
* `backend/test/backend.test.js` – quota and premium expiry, schema validation, value sanitising.
* Manual end-to-end test with two accounts on two devices (see README demo script).

## 8. Limitations and future work

* Payments are simulated; a real gateway (e.g. Paymob) would add commission on PT plans.
* Presence ("online") and read receipts are not implemented.
* Gym search loads all verified gyms; a geohash query would be needed at city scale.
* Arabic localisation and accessibility review are natural next steps.
