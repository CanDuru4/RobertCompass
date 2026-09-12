# Robert Compass

An iOS orienteering app with shared teams, GPS checkpoints, questions, and a live leaderboard. The Xcode project and bundle identity retain the original Radventure names so this can remain an update to the existing app.

## Modernization status

- UIKit app targeting iOS 15 or later, compiled with Xcode 27 and the iOS 27 SDK.
- Firebase Apple SDK 12.19.1 pinned through Swift Package Manager. CocoaPods is no longer required.
- Email/password accounts, verification, recovery, persistent sign-in, and account deletion replace the unavailable school Exchange login.
- Shared lobbies, invite codes, captain controls, server-selected routes, GPS checks, atomic scoring, live results, and paginated history.
- New Firebase project `robert-compass` and iOS app `com.CanDuru.Radventure` created in the owner's current Google account.
- Email/Password provider enabled in that project, with Require enforcement and a minimum password length of 12 confirmed in the console.
- Default Standard Firestore database created in `europe-west1` on Spark, with production-mode rules denying all client access until deployment.
- App Attest registered for `com.CanDuru.Radventure` and Apple team `NV57XZ3KBV`, matching the local Can Duru signing certificates. Physical-device attestation and distribution signing remain unverified.
- Cloud authorization, billing, service setup, and physical device verification remain release gates until completed. Local tests use disposable Firebase emulators.

The retired `radventure-robert` project is rejected by the app. Existing local `GoogleService-Info.plist` and `Keys.plist` files are ignored and are not bundled or read. Old users, questions, routes, and scores require access to the old account or an export. The supplied practice course is explicitly sample data, not an approved campus route.

## Open and run

Open `Radventure.xcodeproj`, select `Radventure`, and let Xcode resolve packages. Do not run `pod install`. Test targets require iOS 17 or later because the current Xcode XCTest framework requires it. Select a signing team you control for a physical device or distribution; the existing team identifier must be confirmed before release.

Without a new configuration file, the app presents a setup screen. For simulator development, select `Radventure Local` after starting the emulators below. This supplies the Debug-only `--emulator` argument. Release builds ignore emulator arguments.

## Local backend and tests

Requirements: Node 22, Java 21 or later, Xcode, and an installed iOS simulator runtime. Dependencies are locked in `backend/package-lock.json` and Xcode's `Package.resolved`.

The backend uses Firebase Admin 14.4.0 and Functions 7.3.2. A `qs` override keeps the HTTP dependency on patched version 6.16.0 or later until upstream ranges catch up. See the [upstream advisory](https://github.com/advisories/GHSA-4mjr-xmp4-gh2g) and [Admin release notes](https://firebase.google.com/support/release-notes/admin/node).

The `gaxios` dependency also uses a scoped `uuid` 11.1.1 override; its only use is the compatible `v4()` boundary generator. Development-only Firebase CLI dependencies still have upstream moderate audit advisories. Do not feed the CLI untrusted CSV, archives, or database exports. Production and development audits are checked separately; no automatic major-version downgrade is applied to silence audit output.

```sh
export COMPASS_ROOT=/Users/canduru04/Developer/Swift/Storyboard/RobertCompass
npm --prefix "$COMPASS_ROOT/backend" ci
npm --prefix "$COMPASS_ROOT/backend" run check
npm --prefix "$COMPASS_ROOT/backend" test
"$COMPASS_ROOT/backend/node_modules/.bin/firebase" emulators:start \
  --config "$COMPASS_ROOT/firebase.json" --project demo-robert-compass
```

Keep that terminal running. Services bind only to `127.0.0.1`: Auth 9099, Firestore 8080, Functions 5001, and emulator UI 4000. Do not start a second instance on these ports. In another terminal, run integration tests before seeding the UI fixtures because those tests clear the disposable demo database:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  npm --prefix "$COMPASS_ROOT/backend" run test:integration
node "$COMPASS_ROOT/backend/scripts/seed.js"
node "$COMPASS_ROOT/backend/scripts/prepare-ui.js"
```

The fixture player's explicitly fake credentials are in `backend/scripts/prepare-ui.js`. They work only in the Auth emulator. The seed command creates rather than overwrites a course. Run it once per cleared demo database. Never run integration tests against data you need to keep.

Use a dedicated simulator. Replace `SIMULATOR_UUID` below with its identifier. Install/build the app before granting location permission, or choose Allow While Using App in the simulator.

```sh
xcrun simctl location SIMULATOR_UUID set 41.0000,29.0000
xcrun simctl privacy SIMULATOR_UUID grant location com.CanDuru.Radventure
xcodebuild -project "$COMPASS_ROOT/Radventure.xcodeproj" -scheme Radventure \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath "$COMPASS_ROOT/build/DerivedData" \
  -clonedSourcePackagesDirPath "$COMPASS_ROOT/build/SourcePackages" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGN_IDENTITY=- test
```

Use ad hoc simulator signing as shown. `CODE_SIGNING_ALLOWED=NO` can prevent Firebase Auth from accessing the simulator keychain. Swift tests cover decoding, stable IDs, deadline boundaries, suspension across midnight, and duration formatting. Backend tests cover verified identity, access rules, concurrent joins/answers, expiry, captain/admin controls, and deletion. UI tests exercise sign-in, team creation, both question styles, results, history, and relaunch restoration.

## Connect the new cloud project

[Open Robert Compass in Firebase](https://console.firebase.google.com/project/robert-compass/overview). `.firebaserc` deliberately defaults to the disposable demo project; live commands must explicitly target `robert-compass`.

1. Authorize the official Firebase CLI with the project owner's account. Never commit service-account private keys or CLI refresh tokens.
2. Create the default Firestore database in `europe-west1`, initially in production mode. Enable Authentication with Email/Password, set minimum password length to 12, and review verification/recovery email templates. Players must verify their address before reading course data.
3. Download the Apple configuration for `com.CanDuru.Radventure`. Save it locally as `Radventure/Configuration/FirebaseConfig.plist`. The build copies that file if present; Git ignores it. Other bundles and the retired project are rejected.
4. Register App Check using App Attest and your confirmed Apple Developer team. Test on a physical device. Simulator development uses emulators because App Attest is unavailable there.
5. Enable Blaze only after owner approval of billing. Cloud Functions deployment requires billing. Functions use Node 22 in `europe-west1`, zero minimum instances, and at most three instances per function. These limits are not a spending cap. Set Google Cloud billing alerts.
6. Deploy the verified rules, indexes, and functions:

```sh
"$COMPASS_ROOT/backend/node_modules/.bin/firebase" deploy \
  --config "$COMPASS_ROOT/firebase.json" --project robert-compass \
  --only firestore:rules,firestore:indexes,functions
```

7. Wait for indexes to finish building, import a reviewed course, and test two real accounts on physical devices. Verify email delivery/recovery, App Check, team joining, simultaneous scoring, background/resume, location denial, history, sign-out, and deletion before distribution.

Production callables enforce App Check and require an existing, enabled, email-verified user. Firestore denies all client writes. Do not weaken these rules to work around configuration errors. Analytics, notifications, Crashlytics, and school OAuth are not required.

## Course import

Run `node backend/scripts/seed.js --project robert-compass --file /absolute/course.json` to validate without writing. Add `--apply` after reviewing its course ID, dates, coordinates, rules, and answers. Live import requires owner-controlled Application Default Credentials, not the iOS configuration key. Configure local Google credentials or execute in Google Cloud Shell; never commit credential files.

The input is one JSON object:

| Field | Format |
| --- | --- |
| `id` | Unique letters, digits, underscores, or hyphens; existing IDs are never overwritten |
| `name`, `rules` | Display name and complete player rules |
| `startsAt`, `endsAt` | Epoch milliseconds; end strictly after start |
| `durationSeconds` | Integer 60 to 86400 |
| `maxTeamSize` | Integer 1 to 20 |
| `latitude`, `longitude` | Reviewed map center |
| `published` | Boolean; only true makes the course visible |
| `entryCode` | Optional invitation code, up to 128 characters |
| `routes` | 1 to 20 arrays of unique, existing checkpoint IDs |
| `checkpoints` | 1 to 100 checkpoint objects |

A checkpoint contains `id`, `name`, `question`, `options` (up to eight choices, empty for free text), `answers`, `latitude`, `longitude`, `radiusMeters` (10 to 500), and `points` (1 to 10000). Answers normalize case, Unicode, and extra whitespace; accents and punctuation remain significant.

The importer separates answers and a SHA-256 entry-code hash into server-only `privateGames`. Only whitelisted public fields are published. Routes become maps containing `checkpointIds`, because Firestore does not support nested arrays. Organizers must approve coordinates before real participants use them.

## Data and authorization

| Collection | Access and purpose |
| --- | --- |
| `users/{uid}` | Owner reads own display name and current session pointer; server writes |
| `games/{id}` | Verified users read published courses and public checkpoints |
| `games/{id}/leaderboard/{sessionId}` | Verified users read team name, score, elapsed time, status |
| `sessions/{id}` | Members read their team's membership, route, progress, and invite code |
| `privateGames/{id}` | Server only, answers and optional entry-code hash |
| `joinCodes/{code}` | Server only, invite lookup |

Scores and deadlines are calculated in server transactions. Retried or simultaneous correct answers award points once. Captains start/end teams; members can leave a waiting lobby. Admin cancellation requires a signed `admin: true` custom claim assigned through trusted server administration, never a password embedded in the app.

The app requests recent precise location to center the map or submit an answer. Raw locations are not stored in Firestore by this implementation. Client GPS is not proof against a compromised device.

Deletion requires recent password reauthentication and no open activity. It deletes the Auth account, removes personal membership/name fields from shared history, transfers captain ownership if needed, and anonymizes empty teams while preserving scores. An anonymous UID tombstone prevents in-flight requests from recreating the profile. Retry interrupted cleanup to finish deletion. The owner's privacy policy must describe retention and platform logging before publication.

## Release limits

Verified locally on September 12, 2026: Debug simulator build, Release iPhone build (unsigned), 7 Swift tests, 2 simulator UI scenarios, 6 backend domain tests, and 17 Firestore/Auth/Functions integration tests all passed. The UI scenario restores an active session after termination, completes both sample checkpoints for 200 points, and checks the leaderboard, history, and completed-session restoration. Production dependency audit reports zero vulnerabilities; the full development dependency audit retains five moderate upstream advisories.

Local evidence is under ignored `build/ios-final.xcresult`, `build/ios-final.log`, `build/integration-verified.log`, and `build/release-final.log`. Live service deployment has not been verified.

- Simulator compilation does not verify every supported iOS version. Test the oldest supported device and current production iOS before App Store submission.
- Cloud setup, App Attest, Apple signing ownership, and real email delivery need verification after the account/billing steps.
- Leaderboard displays the top 100 teams and labels that limit. History loads 25 entries per page.
- Expiry is enforced on every answer even while the client is suspended. Expired records finalize when a member reconnects; no recurring paid cleanup job is configured.
- Old course content/history needs an export or reconstruction from the organizer.

## References

- [Firebase Apple SDK releases](https://firebase.google.com/support/release-notes/ios)
- [Xcode requirements](https://developer.apple.com/xcode/system-requirements/)
- [Email/password authentication](https://firebase.google.com/docs/auth/ios/password-auth)
- [Callable functions](https://firebase.google.com/docs/functions/callable)
- [Functions runtime and billing](https://firebase.google.com/docs/functions/manage-functions)
- [App Attest](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Firestore emulators](https://firebase.google.com/docs/emulator-suite/connect_firestore)

Can Duru, [GitHub](https://github.com/CanDuru4)
