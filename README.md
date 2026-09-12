# Robert Compass

An iOS orienteering app with shared teams, GPS checkpoints, questions, and a live leaderboard. The Xcode project and bundle identity retain the original Radventure names so this can remain an update to the existing app.

## Modernization status

- UIKit app targeting iOS 15 or later, compiled with Xcode 27 and the iOS 27 SDK.
- Firebase Apple SDK 12.19.1 pinned through Swift Package Manager. CocoaPods is no longer required.
- Email/password accounts, verification, recovery, persistent sign-in, and account deletion replace the unavailable school Exchange login.
- Shared lobbies, invite codes, captain controls, deterministic route assignment, GPS checks, atomic scoring, live results, and paginated history.
- New Firebase project `robert-compass` and iOS app `com.CanDuru.Radventure` created in the owner's current Google account.
- Email/Password provider enabled in that project, with Require enforcement and a minimum password length of 12 confirmed in the console.
- Default Standard Firestore database created in `europe-west1` on Spark. Tested access rules and indexes are deployed to the live project.
- Firebase CLI authorization is complete, and the new Apple configuration is downloaded into the ignored local configuration folder.
- App Attest registered for `com.CanDuru.Radventure` and Apple team `NV57XZ3KBV`. The signed app passed all eight unit/device checks on the owner's iPhone 17 Pro Max running iOS 27, including a real Firebase App Attest token exchange.
- The app runs entirely on Firebase Spark: Authentication, Firestore transactions, and security rules. No Cloud Functions, external server, billing account, or paid plan is required. Do not enable Blaze. Local tests use disposable Firebase emulators.

The retired `radventure-robert` project is rejected by the app. Its old `GoogleService-Info.plist` and `Keys.plist` have been moved out of the app folder into the ignored cleanup recovery folder and are never bundled or read. Local Firebase exports were found under `Extra Files/Old Files/Firebase JSON Files` and preserved. Their contents have not been validated or migrated; recovering original users, questions, routes, or scores requires reviewing those exports. The local practice course is emulator sample data. The live Robert College Starter course uses the campus center supplied by the owner and six mapped footpath checkpoints. Its positions have not been walked on site.

## Open and run

Open `Radventure.xcodeproj`, select `Radventure`, and let Xcode resolve packages. Do not run `pod install`. Test targets require iOS 17 or later because the current Xcode XCTest framework requires it. Select a signing team you control for a physical device or distribution; the existing team identifier must be confirmed before release.

Without a new configuration file, the app presents a setup screen. For simulator development, select `Radventure Local` after starting the emulators below. This supplies the Debug-only `--emulator` argument. Release builds ignore emulator arguments.

The obsolete top-level `Radventure.xcworkspace`, empty Pods/Translation/Frameworks groups, Microsoft sign-in artwork, retired Cloud Functions service and tests, and superseded read-only rules have been removed from the active project. Open the `.xcodeproj` directly. Its embedded `project.xcworkspace` and `Package.resolved` remain because Swift Package Manager uses them. Files retired during cleanup are recoverable under the ignored `build/cleanup-recovery-2026-09-12` folder or from Git history.

Keep `Radventure/Configuration/FirebaseConfig.plist`, `courses`, and `Extra Files`. The ignored `build` folder also holds local Firebase CLI authorization, the Node runtime, dependency caches, and verification evidence, so do not delete it wholesale when clearing build products.

## Local backend and tests

Requirements: Node 22, Java 21 or later, Xcode, and an installed iOS simulator runtime. Dependencies are locked in `backend/package-lock.json` and Xcode's `Package.resolved`.

Organizer tools use Firebase Admin 14.4.0, Firestore 9.1.0, and Google Auth Library 10.9.1. `backend/src/domain.js` contains only the import validation and answer-normalization helpers; the retired server code and `firebase-functions` dependency have been removed. A `qs` override keeps the HTTP dependency on patched version 6.16.0 or later until upstream ranges catch up. See the [upstream advisory](https://github.com/advisories/GHSA-4mjr-xmp4-gh2g) and [Admin release notes](https://firebase.google.com/support/release-notes/admin/node).

The `gaxios` dependency also uses a scoped `uuid` 11.1.1 override; its only use is the compatible `v4()` boundary generator. Development-only Firebase CLI dependencies still have upstream moderate audit advisories. Do not feed the CLI untrusted CSV, archives, or database exports. Production and development audits are checked separately; no automatic major-version downgrade is applied to silence audit output.

```sh
export COMPASS_ROOT=/Users/canduru04/Developer/Swift/Storyboard/RobertCompass
npm --prefix "$COMPASS_ROOT/backend" ci
npm --prefix "$COMPASS_ROOT/backend" run check
npm --prefix "$COMPASS_ROOT/backend" test
"$COMPASS_ROOT/backend/node_modules/.bin/firebase" emulators:start \
  --config "$COMPASS_ROOT/firebase.json" --project demo-robert-compass
```

Keep that terminal running. Services bind only to `127.0.0.1`: Auth 9099, Firestore 8080, and emulator UI 4000. Do not start a second instance on these ports. In another terminal, run the Spark security tests, then seed the UI fixtures. Spark tests clear only their separate `demo-compass-spark-tests` namespace:

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

Use ad hoc simulator signing as shown. `CODE_SIGNING_ALLOWED=NO` can prevent Firebase Auth from accessing the simulator keychain. Swift tests cover decoding, stable IDs, deadline boundaries, suspension across midnight, and duration formatting. Spark tests use client SDKs to verify identity, atomic profile pointers, invite lookup, concurrent joins and answers, capacity, entry codes, precise-location and clock checks, expiry, captain controls, private data, score forgery, and deletion. UI tests exercise sign-in, team creation, both question styles, results, history, and relaunch restoration. They supply a fresh location at each checkpoint through XCTest and restore the previous simulated location afterward. An interrupted fixture activity is ended through the normal captain controls before the next run.

## Connect the new cloud project

[Open Robert Compass in Firebase](https://console.firebase.google.com/project/robert-compass/overview). `.firebaserc` deliberately defaults to the disposable demo project; live commands must explicitly target `robert-compass`.

1. Authorize the official Firebase CLI with the project owner's account. Authorization is already complete on this checkout and stored under the ignored `build/firebase-cli` directory. Set `export XDG_CONFIG_HOME="$COMPASS_ROOT/build/firebase-cli"` before using the local CLI to reuse that authorization. Never commit service-account private keys or CLI refresh tokens.
2. Create the default Firestore database in `europe-west1`, initially in production mode. Enable Authentication with Email/Password, set minimum password length to 12, and review verification/recovery email templates. Players must verify their address before reading course data.
3. Download the Apple configuration for `com.CanDuru.Radventure`. Save it locally as `Radventure/Configuration/FirebaseConfig.plist`. Xcode copies the `Configuration` resource folder using its standard resource phase, including when it contains no configuration file. Keep only the Apple client configuration in this folder; never put private keys here. Git ignores the configuration. Other bundles and the retired project are rejected.
4. Register App Check using App Attest and your confirmed Apple Developer team. Test on a physical device. Simulator development uses emulators because App Attest is unavailable there.
5. Keep the project on Spark. Gameplay writes go directly through Firestore transactions checked by `firestore.spark.rules`. `firebase.json` intentionally contains no Functions deployment. Spark quotas limit capacity; do not attach billing to work around them.
6. Deploy the verified database rules and indexes:

```sh
"$COMPASS_ROOT/backend/node_modules/.bin/firebase" deploy \
  --config "$COMPASS_ROOT/firebase.json" --project robert-compass \
  --only firestore:rules,firestore:indexes
```

7. Import a reviewed course and verify it through the app. Live two-account checks already passed for sign-in, shared teams, captain start, concurrent scoring, leaderboard updates, and account deletion. Check actual email delivery/recovery and walk the starter route before organizing an event. Physical App Attest verification is complete.

Firestore authorizes only verified players and narrowly defined atomic transitions. Private answers remain unreadable to app clients. App Attest is registered and tested, and Firestore App Check enforcement is enabled. The console notes that enforcement can take up to 15 minutes to propagate. Authentication App Check remains in monitoring mode. Analytics, notifications, Crashlytics, and school OAuth are not required.

## Course import

Run `node backend/scripts/seed.js --project robert-compass --file /absolute/course.json` to validate without writing. Add `--apply` after reviewing its course ID, dates, coordinates, rules, and answers. Live import uses owner-controlled Application Default Credentials, or add `--firebase-cli` to reuse the already authorized local CLI with `XDG_CONFIG_HOME="$COMPASS_ROOT/build/firebase-cli"`. The CLI adapter is pinned to Firebase Tools 15.30.0 and keeps access tokens in memory. No service-account key or new login is needed on this checkout.

The input is one JSON object:

| Field | Format |
| --- | --- |
| `id` | Unique letters, digits, underscores, or hyphens; existing IDs are never overwritten |
| `name`, `rules` | Display name and complete player rules |
| `startsAt`, `endsAt` | Safe integer epoch milliseconds; end strictly after start |
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
| `users/{uid}` | Owner reads and updates a validated display name, active pointer, and deletion tombstone |
| `games/{id}` | Verified users read published courses and public checkpoints |
| `games/{id}/leaderboard/{sessionId}` | Verified users read team name, score, elapsed time, status |
| `sessions/{id}` | Members read and atomically update their team; verified invite holders can get an open lobby by its random ID |
| `privateGames/{id}` | Organizer writes only; rules can check answers and entry-code hashes, clients cannot read |
| `joinCodes/{code}` | Verified exact-code lookup, no listing; created atomically with a new team |
| `users/{uid}/attempts/{id}` | Owner-private, rules-validated answer/location receipt used for scoring |
| `users/{uid}/entries/{gameId}` | Owner-private proof of a correct course entry code |

Server timestamps establish creation, start, and answer acceptance times. Rules validate the exact score increase, completed checkpoint, and leaderboard projection together using `getAfter()`. Retried or simultaneous answers award points once. Route assignment uses the creation timestamp modulo the course route count; it is deterministic, not cryptographically random. Captains start/end teams; members can leave a waiting lobby. Organizer changes require trusted Firebase administration.

The app requests recent precise location to center the map or submit an answer. A valid answer temporarily stores a private receipt containing the answer, coordinates, accuracy, capture time, and trusted acceptance time. The app deletes the receipt after scoring or a confirmed duplicate. Interrupted receipts older than 24 hours are removed in batches of up to 100 when the player next connects or refreshes; account deletion clears all receipts. There is no scheduled retention job, so abandoned accounts can retain interrupted receipts until cleanup. Client GPS is not proof against a compromised device.

Deletion requires recent password reauthentication and no open activity. It deletes the Auth account, removes personal membership/name fields from shared history, transfers captain ownership if needed, and anonymizes empty teams while preserving scores. An anonymous UID tombstone prevents in-flight requests from recreating the profile. Retry interrupted cleanup to finish deletion. The owner's privacy policy must describe retention and platform logging before publication.

## Live Robert College course

The owner selected campus center `41.066965, 29.035686`. `Robert College Starter` is published as `robert-college-starter-2026`, with six checkpoints, 600 possible points, a 45-minute limit, and teams of up to six. It remains available until September 13, 2027 at 00:00 Istanbul time. Players can choose any checkpoint order.

The full organizer import, including private answers, is kept in the ignored local file `courses/robert-college-starter.private.json`. Do not commit it. Coordinates were selected from mapped footways, not guessed building entrances: [OpenStreetMap campus](https://www.openstreetmap.org/way/473745091), [central and south paths](https://www.openstreetmap.org/way/463590115), [west and north paths](https://www.openstreetmap.org/way/463590117). Map data: OpenStreetMap contributors, ODbL. The Bosphorus question is supported by the [school profile](https://website.robcol.k12.tr/uploads/file/robert-college-school-profile-2022-23.pdf).

The course is labeled an independent starter activity. On-site accessibility has not been verified. Observe current campus access rules and review the points before hosting an event.

## Verification and remaining release checks

The Firebase Spark migration passed eight simulator model tests (including version-2 timestamp/deadline decoding), two gameplay/setup UI scenarios, and 12 client-SDK security/concurrency cases. The full simulator run also passed the existing launch scenario. A live two-account check passed email/password sign-in, shared team creation/joining, captain start, rejected wrong answers, concurrent scoring exactly once, live leaderboard observation, score-forgery rejection, and identity removal/account deletion. Temporary QA accounts and exact QA documents were cleaned up.

Final simulator evidence: `build/spark-final-ios.xcresult` and `build/spark-final-rules.log`. Deployment and live two-client evidence: `build/spark-deploy.log` and `build/spark-live-smoke.log`. Production dependencies report zero audit vulnerabilities in `build/spark-audit.log`.

The final unsigned Release build also passed in `build/spark-final-release.log`. It targets the new Firebase project and has no Firebase Functions product dependency. This verifies compilation and packaging, not App Store distribution signing.

Version 3.0 build 34 was installed and launched on the owner's iPhone. Both physical checks passed in `build/spark-live-device.xcresult`: a fresh App Attest exchange and a full native FirebaseGameService flow covering sign-in, profile creation, team creation, captain start, answer scoring, leaderboard read, and account deletion. These checks ran after Firestore App Check enforcement was enabled. The test used a synthetic location for an isolated temporary course; it does not verify walking the campus route. `build/spark-device-fixture.log` confirms cleanup of the temporary device account and test documents.

To repeat the opt-in device test, choose a fresh random 16-character hexadecimal tag, start `node backend/scripts/device-fixture.js --tag TAG --apply` with the authorized CLI environment, and set `COMPASS_QA_TAG` to that same tag in the RadventureTests target's xctestrun `EnvironmentVariables`. Build for testing first and keep the edited xctestrun beside the generated file so its relative bundle paths remain valid. Run only `RadventureTests/RadventureTests/testLiveGameplayOnPhysicalDevice` and `RadventureTests/RadventureTests/testLiveAppAttestOnPhysicalDevice` on the paired iPhone. The gameplay test skips if the owner is already signed in. The phone generates its temporary password in memory; the helper only verifies the exact tagged test account and cleans its data afterward. No password or token is printed or stored in the test plan.

The opt-in live check is `node backend/scripts/live-smoke.js --project robert-compass --apply`, with the authorized CLI environment above. It creates its own temporary accounts and tests database rules through the client SDK; owner access only creates and cleans test fixtures. It does not send verification or recovery emails. Run it before enabling Firestore App Check enforcement; after enforcement use the signed iPhone app for live checks rather than weakening protection for this script.

- Real inbox verification/recovery and walking all campus checkpoints remain manual acceptance checks.
- Debug and unsigned Release compilation do not establish App Store distribution readiness. Confirm distribution provisioning and test the oldest supported iOS version before submission.
- Leaderboard displays the top 100 teams and labels that limit. History loads 25 entries per page.
- Expiry is enforced for new answer receipts even while the client is suspended. Records finalize when a member reconnects; no paid cleanup service is configured.
- Original Firebase exports are preserved locally, but recovering usable historical data from them has not been attempted.

## References

- [Firebase Apple SDK releases](https://firebase.google.com/support/release-notes/ios)
- [Xcode requirements](https://developer.apple.com/xcode/system-requirements/)
- [Email/password authentication](https://firebase.google.com/docs/auth/ios/password-auth)
- [Firebase Spark pricing and quotas](https://firebase.google.com/pricing)
- [Atomic security-rule validation](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [App Attest](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Firestore emulators](https://firebase.google.com/docs/emulator-suite/connect_firestore)

Can Duru, [GitHub](https://github.com/CanDuru4)
