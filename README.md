# ICA 16 Class A — Cloud Quiz (Graduate)

Flutter quiz using the exact OpenTDB Class A request, Firebase Email/Password authentication, and an immutable Firestore attempt verified with a server-only read.

## One-time setup

1. Install Flutter and Firebase CLI, then run `flutter create .` to generate platform folders if they are absent.
2. Run `flutter pub get`.
3. Create a Firebase project, enable Email/Password Authentication, create two test users, and create a Firestore Native-mode database.
4. Run `dart pub global activate flutterfire_cli`, then `flutterfire configure` from this directory and select the real Android app/project. Never commit credentials.
5. In `android/app/src/main/AndroidManifest.xml`, ensure this line is directly under `<manifest>`:
   `<uses-permission android:name="android.permission.INTERNET" />`
6. Deploy the checked-in rules with `firebase deploy --only firestore:rules`.
7. Run `flutter test`, then `flutter run`. Test on two authenticated clients for G01/G02.

The app initializes Firebase from native configuration. `flutterfire configure` supplies the Android configuration. If using generated Dart options instead, update `main.dart` to pass `DefaultFirebaseOptions.currentPlatform` as required by FlutterFire.

## Cloud contract

Path: `users/{authenticatedUid}/attempts/{roundId}`. The document contains exactly `schemaVersion`, `variant`, `categoryId`, `questionCount`, `correctCount`, and `submittedAt`. A transaction creates it once or accepts an identical existing payload; a mismatch is a collision. Verification uses `GetOptions(source: Source.server)`, checks all six fields, a resolved timestamp, and no pending writes.

## Development fault injection

`AttemptRepository.fault` supports labelled `hideAcknowledgement`, `unavailable`, and `resourceExhausted` cases. Keep it at `none` for release. The acknowledgement injection runs the real transaction first, then hides completion. Reconcile reads the same document ID from the server. Do not use emulator-only results for required deployed-cloud evidence.

## Release and evidence

Complete [EVIDENCE_TEMPLATE.md](EVIDENCE_TEMPLATE.md) with real observations and screenshots, then export it as `ICA16_A_YourName.docx`. Build with `flutter build apk --release`, install-test it, and rename the output `ICA16_A_YourName.apk`. Replace `YourName` with your actual name.

Never commit passwords, tokens, service-account files, keystores, or test-user credentials. Share grader credentials only through the instructor-approved private channel.

