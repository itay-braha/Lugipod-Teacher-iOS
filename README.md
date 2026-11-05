# לוגיפוד למורים — Lugipod Teacher (iPad / iPhone)

A native SwiftUI app for Lugipod **teachers** (teachers only; not the general Lugipod app).

- **Home**: the week's lessons with a live phase and a join button, and the lesson summaries still owed.
- **Alerts**: the bell, natively, plus **push notifications** for every new alert.
- **Lesson room + screen share**: an iPad browser cannot share the screen or keep the microphone alive
  with Notability in front. The room page runs inside the app, and a native Daily client carries the
  teacher's voice (background audio) and the system screen share (broadcast extension).
- **More**: the screens not ported yet (full board, availability, economy, vault, SOS) open the Lugipod
  website inside the app, signed in with the app's own session.

Architecture, API and push setup live in the Lugipod repo: `docs/IOS_TEACHER_APP.md`.

## How it fits together

```
 SwiftUI (native)                          Lugipod backend (Next.js on Vercel)
 ────────────────                          ───────────────────────────────────
 LoginView  ── phone ───────────────────►  POST /api/native/otp-request  (WhatsApp code)
            ── code  ──► Supabase Auth (SDK verifies, session in the Keychain)
 HomeView   ── Bearer ──────────────────►  GET  /api/native/home
 AlertsView ── Bearer ──────────────────►  GET/POST /api/native/alerts
 Push       ── token ───────────────────►  POST/DELETE /api/native/push   ◄── pg_cron → APNs
 WebScreen  ── session form post ───────►  POST /api/native/web-login  (cookies for the web pages)
 Lesson room (web page in WebScreen) ◄─ bridge ─► CallManager (native Daily client + screen share)
                                           POST /api/meeting/native-join, /api/meeting/state
```

## Build and test

CI (`.github/workflows/ios.yml`, free on a public repo) generates the project with XcodeGen, builds and
runs the unit tests on an iPad simulator, and checks that an unsigned Release archive embeds the
screen-share extension and the privacy manifest. Locally (Mac): `cd ios && xcodegen && open LugipodTeacher.xcodeproj`.

The Supabase connection (public host + publishable key) comes from `ios/Config/Secrets.xcconfig`
(git-ignored; see `Secrets.example.xcconfig`). The TestFlight workflow writes it from the repository
secrets `SUPABASE_PROJECT_HOST` and `SUPABASE_PUBLISHABLE_KEY`. Without it the app shows a setup screen.

The simulator cannot run a system broadcast, the microphone, or APNs, so those need a real iPad:

1. Sign in, allow notifications.
2. Open a live lesson, join. The bar at the bottom shows "בשיחה"; students hear the teacher.
3. Tap "שיתוף מסך" in the room, pick **שיתוף מסך**, Start Broadcast; switch to Notability.
4. Check no echo or double audio on either side.
5. With the lesson closed, create an alert (for example finish a lesson) and check the push arrives.

## Releasing (needs the Apple Developer account)

Repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`,
`SUPABASE_PROJECT_HOST`, `SUPABASE_PUBLISHABLE_KEY`. Run the **TestFlight** workflow. Bundle ids
`com.itaybraha.lugipod.teacher` and `….screen`, app group `group.com.itaybraha.lugipod`.
Push also needs, on the server (Vercel), `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`.
