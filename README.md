# לוגיפוד למורים — Lugipod Teacher (iPad)

A thin native iPad/iPhone app for Lugipod teachers. It exists for one reason: an iPad browser
cannot share the screen (WebKit has no `getDisplayMedia`) and cannot keep the microphone alive
while another app (Notability) is in front. This app can, so a teacher can teach from Notability
and still be heard and seen by the students inside the Lugipod lesson.

It is a shell around the Lugipod site (`https://lugipod.com/teacher`, same login, same pages),
plus a native Daily call client. It will later be folded into the full Lugipod app.

## How it works

```
 WKWebView (lugipod.com)                         native
 ───────────────────────                         ──────
 /meeting/lesson/<id>   ── startCall ──────────► CallManager
   (joins Daily MUTED,                            POST /api/meeting/native-join
    heartbeat, files, end)                        joins the room as "<name> · iPad":
                                                    mic ON (works in the background)
 "שיתוף מסך" button     ── startShare ─────────►  ShareLauncher → iOS broadcast sheet
                                                   → LugipodScreenCapture extension
                                                   → Daily (DailySystemBroadcast) → room
 share button state     ◄── lugipod-native event ─ CallManager
```

* The page detects the app by the `LugipodTeacherApp` user-agent suffix and the
  `webkit.messageHandlers.lugipod` bridge (`src/components/meeting/MeetingRoom.tsx` in the
  Lugipod repo).
* The app never sees credentials: it replays the web view's cookies to `/api/meeting/native-join`
  and `/api/meeting/state` (a presence heartbeat the app keeps going while the web view sleeps).
* The page's own Daily frame is silenced inside the app (a script in `WebShell.swift`) so the
  students are not heard twice (native plays them).

## Build

CI (`.github/workflows/ios.yml`) generates the project with XcodeGen and builds + runs the unit
tests on an iPad simulator. Locally (Mac): `cd ios && xcodegen && open LugipodTeacher.xcodeproj`.

## Testing

The simulator cannot run a system screen broadcast or the microphone, so CI covers the build and
the bridge/parsing logic. The first TestFlight build must be checked on a real iPad:

1. Open the app, sign in as the teacher, open a lesson room, tap "השתתפות".
2. The bar at the bottom shows "בשיחה"; students hear the teacher.
3. Tap "שיתוף מסך", pick **שיתוף מסך** in the iOS sheet, Start Broadcast.
4. Switch to Notability: students keep seeing the screen and hearing the voice.
5. Check no echo or double audio on the teacher's side and no duplicate voice on the students'.

## Releasing (needs the Apple Developer account)

Add the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`, then run the
**TestFlight** workflow. The app group `group.com.itaybraha.lugipod.teacher` and both bundle ids
(`com.itaybraha.lugipod.teacher`, `….screen`) are created by automatic signing.
