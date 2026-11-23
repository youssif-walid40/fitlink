# FitLink

FitLink is a Flutter app that connects **gym-goers**, **personal trainers** and **gym owners** in Egypt.
Members find nearby gyms by GPS, hire a PT and negotiate a plan in the app, chat with their coach,
and photograph an InBody sheet to get an AI explanation and progress analysis.

CSEN1114 Mobile Application Development – GUC, Winter 2026.

---

## 1. What's in this repository

```
fitlink/
├── lib/
│   ├── main.dart / app.dart        App entry, providers, FCM background handler
│   ├── core/                       Theme, router (go_router + guards), validators, shared widgets
│   ├── models/                     AppUser, Gym, PtProfile, Coaching, Chat, Scan …
│   ├── logic/                      Pure Dart: coaching state machine, progress calculator (unit-tested)
│   ├── services/                   Auth, Storage, REST API client, FCM, GPS, ML Kit OCR, Hive/SharedPreferences cache
│   ├── repositories/               Firestore access per feature
│   ├── providers/                  ChangeNotifier state (session, settings, filters, scan history)
│   └── screens/                    auth, home, gyms, trainers, coaching, chat, inbody, profile, pt, owner, admin
├── test/                           Flutter unit tests
├── tool/setup_platforms.dart       Adds permissions / minSdk / Info.plist keys after `flutter create`
├── backend/                        Node.js REST API (Express + firebase-admin + Gemini)
│   ├── src/routes/ai.js            /ai/inbody/extract, /explain, /progress
│   ├── src/routes/notify.js        /notify  (FCM pushes)
│   ├── src/routes/writes.js        /premium/activate, /gyms/sponsor, /reviews
│   ├── src/routes/files.js         /files/upload + /files/* (image storage)
│   ├── scripts/seed.js             Demo accounts, gyms and trainers
│   └── test/                       Backend unit tests (node --test)
├── firestore.rules, firestore.indexes.json, firebase.json
└── TECHNICAL_REPORT.md             Draft of the short technical report
```

## 2. Requirements

| Tool | Version |
|---|---|
| Flutter | **3.35 or newer** (Dart 3.9+) – check with `flutter --version` |
| Node.js | 20 or newer |
| Firebase CLI | `npm install -g firebase-tools` |
| FlutterFire CLI | `dart pub global activate flutterfire_cli` |
| A Firebase project | The free **Spark** plan is enough. Firebase Storage is *not* used: images are stored by the FitLink backend (`backend/uploads/`). |
| Gemini API key | Free from <https://aistudio.google.com/apikey>. Optional: set `MOCK_AI=true` to demo without one. |

## 3. Setup (about 20 minutes)

### 3.1 Open the project and generate the platform folders

```bash
cd fitlink
flutter create . --org com.fitlink --platforms android,ios   # adds android/ and ios/, keeps lib/
dart run tool/setup_platforms.dart                            # permissions, minSdk 23, iOS keys
flutter pub get
```

> If `flutter pub get` reports a version conflict (package versions move fast), run
> `flutter pub upgrade --major-versions`.

### 3.2 Create and connect Firebase

1. In the [Firebase console](https://console.firebase.google.com) create a project.
2. **Authentication** → Sign-in method → enable **Email/Password**.
3. **Firestore Database** → Create database (production mode, region `eur3` or the closest to Egypt).
4. **Cloud Messaging** is on by default. For iOS push you also need to upload an APNs key (Project settings → Cloud Messaging).
5. Connect the app (this overwrites `lib/firebase_options.dart` and adds `google-services.json`):

```bash
firebase login
flutterfire configure        # pick your project, select android + ios
```

6. Deploy the security rules and indexes:

```bash
firebase use --add            # choose your project
firebase deploy --only firestore:rules,firestore:indexes
```

### 3.3 Run the backend

1. Firebase console → Project settings → **Service accounts** → *Generate new private key*.
   Save it as `backend/service-account.json` (it is git-ignored).
2. Configure and start:

```bash
cd backend
cp .env.example .env          # then set GEMINI_API_KEY (or MOCK_AI=true)
npm install
npm run seed                  # demo accounts, 5 gyms, 4 trainers
npm start                     # http://localhost:8080  (check http://localhost:8080/health)
```

### 3.4 Run the app

The app reaches the backend through `BACKEND_URL`:

| Where the app runs | Command |
|---|---|
| Android emulator | `flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8080` (this is also the default) |
| iOS simulator | `flutter run --dart-define=BACKEND_URL=http://localhost:8080` |
| Physical phone (same Wi-Fi) | `flutter run --dart-define=BACKEND_URL=http://<your-PC-LAN-IP>:8080` |

**VS Code:** add this to `.vscode/launch.json` to press F5:

```json
{
  "version": "0.2.0",
  "configurations": [
    { "name": "FitLink", "request": "launch", "type": "dart",
      "args": ["--dart-define=BACKEND_URL=http://10.0.2.2:8080"] }
  ]
}
```

For push notifications on Android, use an emulator image **with Google Play** (or a real phone).

## 4. Demo accounts

Created by `npm run seed`. Password for all: **`Passw0rd!`**

| Email | Role | Notes |
|---|---|---|
| member@fitlink.app | Member | Joined Iron Hub Gym (Plus tier) |
| member2@fitlink.app | Member | No gym yet |
| karim@fitlink.app | PT | Coach Karim Hassan – online + in-gym at Iron Hub |
| mona@fitlink.app | PT | Online coach |
| ahmed@fitlink.app | PT | Gym affiliation pending owner approval |
| newcoach@fitlink.app | PT | Waiting for admin verification |
| owner@fitlink.app | Gym owner | Owns Iron Hub Gym (sponsored) |
| admin@fitlink.app | Admin | Verifies trainers/gyms, handles reports |

### Live demo script (two devices)

1. **Device A** – log in as `member@fitlink.app`. Gyms tab: GPS list with the sponsored gym first, Map toggle, filters.
2. Trainers → *My gym* → Coach Karim → **Book a plan** → send the request.
3. **Device B** – log in as `karim@fitlink.app`. A push arrives; tap it to open the request. **Accept**, then **Send plan proposal**.
4. Device A gets a push; the proposal also appears in the chat. Tap **Counter**, change the weeks or price.
5. Device B: **Accept counter** → the plan is active on both screens instantly.
6. Device A: InBody tab → photograph a sheet → ML Kit pre-check → AI extraction → confirm values → AI explanation → **Share with trainer**.
7. Device B opens the shared scan from the chat. Marks the coaching **completed**.
8. Device A leaves a verified **review**; Karim's rating updates.
9. Optional: `owner@fitlink.app` approves Ahmed's affiliation; `admin@fitlink.app` verifies Coach Laila.

## 5. Testing

```bash
flutter test                  # progress calculator, coaching state machine, validators, OCR pre-check
flutter analyze
cd backend && npm test        # quota logic, schema validation, value sanitising
```

## 6. How the requirements are covered

| Requirement | Where |
|---|---|
| A. UI/UX – consistent design, validation, loading/empty/error states | `core/theme.dart`, `core/widgets/common.dart` (`LiveView`, `EmptyView`, `ErrorView`), `core/validators.dart` |
| B. Firebase Auth, persistent sessions, profiles with images, roles | `services/auth_service.dart`, `providers/session_provider.dart`, `screens/profile/`, roles in `models/app_user.dart` |
| C. Firestore, media storage, REST API, security rules | `repositories/`, `services/storage_service.dart` → backend media store (`backend/src/routes/files.js`, the "other storage backend" option), `services/api_service.dart`, `firestore.rules` |
| D. Provider + StreamProvider | `app.dart` (`SignedInScope` live streams), `providers/`, `core/live_data.dart`; screen-level StreamProviders in gym/trainer/coaching/chat/scan screens |
| E. Navigation – routing, params, protected routes, back behaviour | `core/router.dart` (role guards, `/coaching/:id`, `/scan/:memberId/:scanId`), `goBack()` falls back to `/home` for notification deep links |
| F. AI on user data | ML Kit pre-check (`services/ocr_service.dart`), Gemini extraction/explanation/progress (`backend/src/routes/ai.js`), deterministic maths (`logic/progress_calculator.dart`) |
| G. Camera/gallery + extra capability | `image_picker` (InBody, avatar, chat, gym, transformations); **GPS** (`services/location_service.dart`) + OpenStreetMap |
| H. FCM, foreground/background, open screen on tap | `services/notification_service.dart`, `main.dart` background handler, `backend/src/routes/notify.js` |
| I. Local persistence | Hive gym/PT cache + SharedPreferences theme, last location, chat & proposal drafts (`services/cache_service.dart`) |
| J. Two-user workflow, persisted and real-time | `logic/coaching_flow.dart`, `repositories/coaching_repository.dart`, `screens/coaching/`, chat |
| Optional | Maps, search/filtering, simulated payments, analytics charts, dark mode, admin moderation |

## 7. Security notes

* The Gemini key lives only in `backend/.env`; the app never sees it.
* Every backend call carries a Firebase ID token, verified server-side, and AI routes are rate-limited per user.
* `role`, `isPremium`, `aiUsage`, `verified`, `sponsored`, ratings and reviews cannot be written from the app (see `firestore.rules`).
* Uploaded images get a random 128-bit token in their file name, so URLs can't be guessed (the same model as Firebase download URLs). Upload permissions mirror Storage rules: owner-only for avatars and scans, the gym owner for gym photos, participants for chat images.
* InBody scans are private. A PT can read one only after the member taps **Share**, which adds the PT to that scan's `sharedWith`.
* `usesCleartextTraffic` is enabled only so the emulator can reach `http://10.0.2.2`. Use HTTPS for any real deployment.

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| "A Firestore index is still building" | Wait 1–3 minutes after `firebase deploy --only firestore:indexes`. |
| `Could not reach the FitLink server` | Check `npm start` is running and `BACKEND_URL` matches your device (see 3.4). |
| AI returns 503 | `GEMINI_API_KEY` missing in `backend/.env`, or set `MOCK_AI=true`. |
| No push on Android emulator | Use a Google Play system image, allow notifications, and make sure both accounts logged in once (tokens are saved on login). |
| Images don't load on a real phone | Images are served by the backend: run the app with `BACKEND_URL` set to your PC's LAN IP. |
| `minSdkVersion` error | Re-run `dart run tool/setup_platforms.dart` (sets minSdk 23). |
| iOS pod errors | In `ios/`: `pod repo update && pod install`; iOS deployment target must be 15.5+. |
