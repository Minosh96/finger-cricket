# 🏏 Finger Cricket – Online Hand Cricket Challenge

A two-player hand-cricket game for Android (Flutter + Firebase).

**Rules:** gestures 1–5 are fingers, 👍 thumb only = 6, 🤙 thumb + pinky = 7. Both players choose secretly within 3 seconds. Matching gestures mean OUT; otherwise the batter scores their number. There is 1 wicket per innings, and a match is 2 overs by default.
**Timeouts:** if the bowler misses, it's a no-ball: +1 run, and the ball doesn't count. If the batter misses, it's a legal dot ball. If both miss, the ball is replayed. Online, a player who misses 4 balls in a row forfeits.

| Mode | Needs | Status |
|---|---|---|
| **Pass & Play** – 2 players, 1 phone, face to face | nothing | works in the first APK |
| **Play Online** – 2 phones, 6-digit room code | Firebase (Part B) | switches on after setup |

---

## Part A – Get the APK from GitHub (≈10 minutes, no Flutter install needed)

GitHub's servers build the app for you, using `.github/workflows/build-apk.yml`.

1. **Create an empty repository** on github.com, for example `finger-cricket`. Leave README, .gitignore and license unticked.
2. **Push this folder** from a terminal inside the unzipped `finger_cricket` folder:
   ```bash
   git init
   git add .
   git commit -m "Finger Cricket v1"
   git branch -M main
   git remote add origin https://github.com/<your-username>/finger-cricket.git
   git push -u origin main
   ```
3. Open the repo → **Actions** tab → **Build APK**. The run takes about 6–10 minutes. Wait for the green ✓.
   If Actions is disabled, click *"I understand my workflows, go ahead and enable them"*, then **Run workflow**.
4. Open the finished run → **Artifacts** → download **finger-cricket-apk** (a .zip). Unzip it to get `app-release.apk`.
5. **Install on Android:** copy the APK to the phone and tap it. Allow *"Install unknown apps"* for your file manager or browser when asked.
6. *(Optional, nicer download link)* Create a version tag. The APK is then attached to a **GitHub Release**:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
   You can now share **Releases → v1.0.0 → app-release.apk** with friends.

> If a build fails: open the failed step in the Actions log. The step names say what was running (tests, Gradle, etc.).

---

## Part B – Turn on online play (Firebase)

Online play uses **Anonymous Auth**, **Realtime Database** and **Cloud Functions**.
⚠️ Cloud Functions require the **Blaze (pay-as-you-go)** plan. A casual game normally stays inside the free allowance, but **set a budget alert** (e.g. US$1) in Google Cloud Billing.

You need these installed on your PC: Flutter SDK, Node.js 22, and Git.

1. **Create the Firebase project.** At https://console.firebase.google.com click *Add project* and name it `finger-cricket`. Then:
   - **Build → Authentication → Get started → Sign-in method → Anonymous → Enable**
   - **Build → Realtime Database → Create database** → location **Singapore (asia-southeast1)** → *Start in locked mode*
   - **Upgrade** to the Blaze plan (bottom-left of the console) and add a budget alert.
2. **Install the CLIs** (one time):
   ```bash
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   ```
3. **Generate the Android project and connect Firebase.** Run these in the repo folder:
   ```bash
   flutter create --platforms=android --org com.melow.fingercricket --project-name finger_cricket .
   flutterfire configure --project=<your-firebase-project-id> --platforms=android
   ```
   This replaces `lib/firebase_options.dart` with your real config, which includes the database URL. That's why the database must be created first.
4. **Deploy the backend** (game engine + security rules):
   ```bash
   firebase use --add            # pick your project, alias: default
   cd functions && npm install && npm test && cd ..
   firebase deploy --only functions,database
   ```
5. **Rebuild the APK.** Commit and push, and GitHub builds a new APK with online play:
   ```bash
   git add .
   git commit -m "Connect Firebase"
   git push
   ```
   (Committing `firebase_options.dart` / `google-services.json` is normal for Firebase apps. These keys identify the project; they are not passwords. The security rules and server functions protect the data.)
6. **Play:** Player 1 taps **Play Online → Create Room** and shares the 6-digit code. Player 2 taps **Join Room**, both tap **Ready**, and the toss happens.

---

## Run on your own phone/emulator (optional)

```bash
flutter create --platforms=android --org com.melow.fingercricket --project-name finger_cricket .   # once
flutter pub get
flutter test          # rule tests
flutter run           # with a phone connected (USB debugging on)
```

---

## How it works

### Project layout
```
lib/
  main.dart                     app start (Firebase optional)
  core/theme.dart               colours, prefs (nickname, sound), haptics
  game/game_rules.dart          scoring rules, overs, result text
  game/local_match.dart         offline Pass & Play engine
  models/room.dart              parses /rooms/{code}
  services/online_service.dart  auth, callable API, moves, presence, server clock
  screens/                      welcome, how-to-play, local setup/match,
                                online menu (create/join), online game
                                (lobby → toss → match → innings break → result)
  widgets/game_widgets.dart     gesture pad, scoreboard, countdown, reveal, history
functions/src/engine.ts         ⭐ authoritative game engine (pure, unit-tested)
functions/src/index.ts          single callable `api` (createRoom, joinRoom, setOvers,
                                ready, chooseBatBowl, tick, requestRematch, leaveRoom)
database.rules.json             deny-by-default security rules
.github/workflows/build-apk.yml cloud APK build
```

### Database
```
rooms/{code}            public to the 2 members only; written by the server
  status                waiting | lobby | toss | playing | innings_break | completed | abandoned
  settings              { overs, wickets: 1, selectionMs: 3000 }
  players/{uid}         { name, ready, connected, joinedAt, left? }
  toss                  { winnerUid }
  match                 { innings, batterUid, bowlerUid, roundKey, startAt, deadlineAt,
                          score, wickets, legalBalls, noBalls, balls[], target,
                          first{…}, lastResult{…}, misses{uid:n}, startedAt }
  locks/{roundKey}/{uid}  true – shows "🔒 locked" without revealing the number
  result                { winnerUid, tie, reason, text, endedAt }
moves/{code}/{roundKey}/{uid}   secret gesture – nobody can read it, write-once
```

### 3-second synchronisation
1. The server opens a round: `roundKey`, `startAt = now + pause`, `deadlineAt = startAt + 3000`.
2. Each phone shows the countdown using **server time** (`.info/serverTimeOffset`), not its own clock.
3. A tap writes `moves/…/{uid}` and `locks/…/{uid}` in one atomic update. **Database rules** check the server's `now <= deadlineAt + 400 ms`. They also reject a second write, a wrong round, or a player who isn't in this match. Late moves are impossible.
4. When both locks appear, or the deadline passes, either phone calls `tick`. The server resolves the ball inside a **transaction** that is keyed on `roundKey`. A ball can never be scored twice, and duplicate calls are harmless.
5. The result is published with the next round's `startAt`. Phones show the reveal until then.

### Disconnections
`connected` uses `onDisconnect()`. An offline player's turns time out. A bowler timeout gives no-balls, a batter timeout gives dot balls. After 4 missed balls in a row (~25 s of grace to reconnect), the opponent wins by forfeit, so a dropped connection can't create endless no-balls. Leaving mid-match also gives the opponent the win.

### Tests
- `cd functions && npm test` – 11 engine tests: the spec example `2,4,NB,1,W = 8/1 (0.4)`, no-balls not counting, 12-ball innings, chase/tie/defend, idempotent resolution, forfeit, rematch reset.
- `flutter test` – the same rules on the app side.

### Not in v1 (ideas for later)
Sound files, random matchmaking, leaderboards, profiles, iOS build (needs a Mac), an automatic clean-up job for old rooms (old codes are reused after 3 h), and a nickname profanity filter.
