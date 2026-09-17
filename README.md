# Robert Compass

[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org/)
[![UIKit](https://img.shields.io/badge/UIKit-MapKit-2396F3?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/documentation/uikit)
[![iOS](https://img.shields.io/badge/iOS-15.0%2B-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Firebase](https://img.shields.io/badge/Firebase-Spark-FFCA28?style=flat&logo=firebase&logoColor=black)](https://firebase.google.com/pricing)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

Robert Compass is an iOS orienteering game: teams walk a course of GPS checkpoints within a time limit, answer a question at each one, and race on a live leaderboard. It was first built in 2023 for high-school freshmen at Robert College and rebuilt in September 2026 to run entirely on the free Firebase Spark plan, with email/password accounts replacing the unavailable school Exchange login. The Xcode project and bundle identity keep the original `Radventure` names so it can ship as an update to the existing app. A live starter course for the Robert College campus is published; its checkpoints have not yet been walked on site.

> **Context:** Built for Robert College, Istanbul.

## Features

- Email/password accounts with email verification, password recovery, persistent sign-in, and account deletion
- Shared team lobbies with invite codes and captain controls (start, end, leave)
- Deterministic route assignment per team and GPS checks at each checkpoint
- Multiple-choice and free-text questions with atomic, exactly-once scoring
- Live leaderboard (top 100 teams) and paginated activity history
- Course expiry enforced by trusted server timestamps, including while the app is suspended
- Firebase App Check with App Attest on physical devices
- Setup screen when no Firebase configuration is present, and a local emulator mode for development

## Tech stack

| Layer | What is used |
| --- | --- |
| Language / UI | Swift 5.0, UIKit, MapKit, CoreLocation |
| Backend | Firebase Spark plan: Authentication, Cloud Firestore transactions and security rules, App Check (App Attest) |
| Dependencies | Swift Package Manager (Firebase Apple SDK 12.19.1) |
| Organizer tools | Node 22 scripts in `backend/` using Firebase Admin 14.4.0 and Firebase Tools 15.30.0 |
| Local testing | Firebase Auth and Firestore emulators, XCTest, `node --test` |

## Architecture

The app talks directly to Firestore; there are no Cloud Functions, external servers or paid services. All gameplay writes (joining a team, starting, answering, scoring, deleting an account) are Firestore transactions validated by `firestore.spark.rules`, which check the exact score change, checkpoint and leaderboard projection together. Answers and entry-code hashes live in a server-only `privateGames` collection that clients cannot read. Organizers publish courses with `backend/scripts/seed.js`, which validates the course JSON and splits public and private fields. Collection layout and access rules are documented in [docs/OPERATIONS.md](docs/OPERATIONS.md#data-and-authorization).

## Getting started

### Prerequisites

- macOS with Xcode 27 or later
- iOS 15.0 or later on a simulator or device (test targets require iOS 17 or later)
- For local backend work: Node 22 and Java 21 or later (Firebase emulators)
- A physical device for App Attest

### Installation

1. Clone the repository.

   ```bash
   git clone https://github.com/CanDuru4/robert-compass.git
   ```

2. Open `Radventure.xcodeproj`, select the `Radventure` scheme, and let Xcode resolve packages. Do not run `pod install`; CocoaPods is no longer used.
3. Select a signing team you control for a physical device or distribution.
4. Without a Firebase configuration file, the app shows a setup screen. For simulator development, start the local emulators (see [docs/OPERATIONS.md](docs/OPERATIONS.md#local-backend-and-tests)) and run the `Radventure Local` scheme, which passes the Debug-only `--emulator` argument. Release builds ignore emulator arguments.

### Configuration

| File | Purpose |
| --- | --- |
| `Radventure/Configuration/FirebaseConfig.plist` | Apple client configuration for `com.CanDuru.Radventure` from the Firebase console. Git-ignored; never commit it. Configurations for other bundles or the retired `radventure-robert` project are rejected. |
| `.firebaserc` | Defaults to the disposable `demo-robert-compass` project; live commands must target `robert-compass` explicitly |
| `courses/*.private.json` | Local organizer course imports including answers. Git-ignored. |

Firebase CLI authorization, project setup steps, and course import format are in [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Project structure

```
Radventure/
├── AppDelegate.swift, SceneDelegate.swift, TabBarViewController.swift
├── Login/               Account sign-in screen
├── Home/                Game map screen
├── Score Board/         Leaderboard screen
├── Profile/             Profile screen
├── Models/              Game data models
├── Services/            Firebase game service, backend and game store
├── Helper/              App Check, shared UI, location manager, rules screen
├── Configuration/       Local FirebaseConfig.plist (ignored)
└── Assets.xcassets
Radventure.xcodeproj/    Xcode project to open (schemes: Radventure, Radventure Local)
RadventureTests/         Model, deadline and opt-in physical-device tests
RadventureUITests/       Gameplay and setup UI scenarios
backend/                 Organizer scripts, validation helpers and Spark rules tests
firebase.json            Firestore rules/indexes and emulator ports
firestore.spark.rules    Firestore security rules
firestore.indexes.json   Firestore indexes
docs/                    Operations notes; docs/assets holds README images
Images/                  Launch screen logo
CHANGELOG.md             Release history
```

## Testing

```bash
npm --prefix backend ci
npm --prefix backend run check
npm --prefix backend test
```

Firestore rules tests run against the local emulators (`npm --prefix backend run test:integration`), and the app's unit and UI tests run from Xcode or `xcodebuild` against an emulator-backed simulator. Full commands, emulator ports and the September 2026 verification record are in [docs/OPERATIONS.md](docs/OPERATIONS.md#local-backend-and-tests). There is no CI.

## Deployment

The app is built, signed and archived from Xcode. Firestore rules and indexes are deployed with the Firebase CLI to the `robert-compass` project, which must stay on the Spark plan; see [docs/OPERATIONS.md](docs/OPERATIONS.md#firebase-project).

## Screenshots

These screenshots show the original 2023 release with the school login; the current login and team flow differ.

<p align="center">
  <img src="docs/assets/screenshot-login.png" alt="Original school login" width="250">
  <img src="docs/assets/screenshot-map.png" alt="Original campus map" width="250">
  <img src="docs/assets/screenshot-checkpoint.png" alt="Original checkpoint question" width="250">
</p>

<p align="center">
  <img src="docs/assets/screenshot-scoreboard.png" alt="Original scoreboard" width="250">
  <img src="docs/assets/screenshot-force-quit.png" alt="Original administrator prompt" width="250">
  <img src="docs/assets/screenshot-rules.png" alt="Original rules screen" width="250">
</p>

## Known limitations

- Data from the retired `radventure-robert` Firebase project (original 2023 users, questions, routes and scores) was not kept.
- The live starter course's checkpoints have not been walked on site, and real inbox verification/recovery still needs a manual check.
- Spark plan quotas limit capacity. There is no scheduled cleanup job; interrupted answer receipts are removed when a player next connects.
- Client GPS is not proof against a compromised device.
- App Store distribution signing and the oldest supported iOS version have not been tested.

## Acknowledgments

Course coordinates use map data from OpenStreetMap contributors (ODbL). Firebase documentation references are listed in [docs/OPERATIONS.md](docs/OPERATIONS.md#references).

## License

MIT. See [LICENSE](LICENSE). Release history is in [CHANGELOG.md](CHANGELOG.md).

## Author

Can Duru — [canduru.net](https://canduru.net)
