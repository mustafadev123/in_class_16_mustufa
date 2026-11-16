# ICA16 A Graduate Evidence — Mustufa

## Build record and AI disclosure

- Student / level: Mustufa, Graduate
- Device / OS: Samsung SM S731U1, Android 17 (API 37)
- Tested APK: ICA16_A_Mustufa.apk
- Repository: https://github.com/mustafadev123/in_class_16_mustufa
- Final commit: 86d4eef
- Firebase project alias: ica16-a-mustufa
- Test date/time zone: November 16, 2026, America/New_York


## Four development checkpoints

| Phase | Commit | Outcome | Evidence / correction |
|---|---|---|---|
| 1 API/model | 3ef8118 | Exact OpenTDB request, validation, HTML decoding, stable choices | Unit tests passed; phone loaded ten questions. |
| 2 quiz/auth | f4191fa | Authentication, one-answer scoring, feedback, review, and replay | Screenshots 01–04 show sign-in, play, feedback, and review. |
| 3 cloud | 76272c2 | Create-once transaction, collision guard, server read, strict rules | Rules deployed; the phone recorded Cloud verified. |
| 4 delivery | 86d4eef | Firebase configuration, Android build, evidence, and conflict resolution | Release APK built; analysis clean; tests passed. |

## Actual state diagram

```text
signedOut -> loading -> playing -> readyToSubmit -> submitting -> verifying -> cloudVerified
     |          |                          |              |
 authError  requestError              saveUnknown   verificationUnavailable
                                           |              |
                                           +-> verifying <-+

permissionDenied branches from submitting. Retry requires the same UID and roundId.
```

The app uses `view`, `unresolved`, `initiatingUid`, `initiatingRound`, and `roundId` as its main state and identity guards. Sign-out and replay are disabled while a submission is unresolved.

## Graduate concurrency sequence

```text
Client A       Firestore transaction                         Client B
   |---- read same round ID (absent) --------------------------|
   |---- create frozen payload and commit -------------------->|
   |                                      callback retries/read existing
   |                                      compare five fixed fields
   |<----- matching payload is reused; mismatch is collision --|
   |---- server-only verification ----|---- server-only verification
```

## Test log

| ID | Action and expected result | Observed result | Result | Evidence |
|---|---|---|---|---|
| T01 | Valid and invalid sign-in should show success/error without secrets | Valid User A sign-in passed. Invalid sign-in was not recorded. | Partial | 01_signin.png |
| T02 | Load exact Class A request and receive ten valid questions | Ten easy General Knowledge multiple-choice questions loaded on the phone. | Pass | 02_current.png |
| T03 | Inject bad JSON, nonzero code, and nine results | Unit validation exists, but all three UI injections were not run. | Not run | Source/unit tests only |
| T04 | Correct, incorrect, and double tap | Correct feedback appeared; a second tap did not change the locked selection. Mixed answers produced an accurate score. | Pass | 03_correct_double_tap.png |
| T05 | Finish, review all ten, then replay | Ten review entries and score 2/10 appeared. Restart produced a fresh question round. | Pass | 04_review_score.png, 07_restart_same_user.png |
| T06 | Submit online and double tap Submit | One real transaction completed and the exact document passed a server-only read. | Pass | 05_review_submit.png; raw cloud image retained locally |
| T07 | Restart and retrieve saved ID as same user | Restart retained authentication; lookup returned “Cloud verified prior round …cVa3QX.” | Pass | 09_restart_server_verified.png |
| T08 | Offline submit, reconnect, and recover same ID | Not performed on the connected phone. | Not run | — |
| T09 | Hide acknowledgement after a real commit | Injection is implemented, but this deployed test was not performed. | Not run | — |
| T10 | User B reads/writes User A path | Deployed owner-only rules exist, but cross-user operations were not recorded. | Not run | firestore.rules |
| T11 | Score 11, extra field, and update | Rules reject these shapes, but deployed invalid requests were not recorded. | Not run | firestore.rules |
| T12 | Inject unavailable and resource-exhausted | Both labelled repository injections exist, but phone observations were not recorded. | Not run | attempt_repository.dart |
| G01 | Two clients submit same ID and payload | Transaction design supports reconciliation, but two-client deployed evidence was not collected. | Not run | — |
| G02 | Same ID with a different score | Collision logic is implemented, but deployed evidence was not collected. | Not run | — |
| G03 | Delayed response after auth changes | UID/round guards are implemented, but a deployed stale-response trace was not collected. | Not run | — |

## Screenshot evidence

### Sign-in screen

![Sign-in form with no credentials visible](evidence/screenshots/01_signin.png)

### Ten-question Class A round

![Question 1 of 10 loaded from OpenTDB](evidence/screenshots/02_current.png)

### Correct answer and locked double-tap state

![Correct feedback uses text, icon, and color](evidence/screenshots/03_correct_double_tap.png)

### Completed review

![Score and answer review](evidence/screenshots/04_review_score.png)

### Submit section

![Review and submit controls](evidence/screenshots/05_review_submit.png)

### Restart as the same authenticated user

![Fresh round after restart](evidence/screenshots/07_restart_same_user.png)

### Failed-first correction

![Debug assertion discovered during the first restart lookup](evidence/screenshots/08_failed_first_restart_lookup.png)

### Corrected server-only restart lookup

![Cloud verified prior round with redacted suffix](evidence/screenshots/09_restart_server_verified.png)

## Six core responses

### 1. Two success layers

I learned that a successful HTTP request is only the first layer of success. When `QuestionService.fetchQuestions` receives HTTP status 200, it means the phone reached OpenTDB and received a response. It does not prove that OpenTDB supplied a usable quiz. I therefore check `response_code == 0`, which is OpenTDB’s application-level success signal. After that, I still validate the data itself. I require exactly ten results, category “General Knowledge,” easy difficulty, multiple-choice type, one nonempty correct answer, and three nonempty incorrect answers. I decode HTML entities and reject duplicate decoded choices before play begins. In T02, the phone displayed “Question 1 of 10,” proving the complete validation path accepted the response. T03 was not fully run with all three injected failures, so I do not claim that evidence as passed. My unit tests did confirm decoding and duplicate rejection. This separation prevents an HTTP 200 response containing an API error or malformed data from becoming a broken playable round.

### 2. Unknown is not failed

I treat an unknown save result differently from a failed save because a network acknowledgement can disappear after Firestore commits the document. A Dart timeout or hidden completion does not cancel the underlying cloud operation. My state flow therefore moves from `submitting` to `saveUnknown` when the app cannot honestly determine the result. It does not create a new round ID or tell the user the score failed. The recovery action reads the same document ID directly from the server and moves through `verifying`. Only a matching document with all six expected fields, a resolved server timestamp, and no pending writes can produce `cloudVerified`. During the real T06 run, the round ending in `cVa3QX` was committed and verified. T07 then restarted the app and retrieved that same attempt, shown in `09_restart_server_verified.png`. I did not execute the T09 acknowledgement-hiding switch during this session, so I distinguish the implemented recovery design from evidence I actually observed. The UI can honestly say saved only after the matching server read.

### 3. Retry identity

I keep one round ID for the entire completed quiz, including every save or verification retry. If I generated a new ID each time the user pressed retry, a committed first request with a lost acknowledgement could be followed by another document. The user would see one quiz, but Firestore could contain two attempts. Using the same ID changes the retry into an idempotent operation. My transaction reads the exact document first. If it is absent, the transaction creates it. If it already exists, the code compares the five fixed non-timestamp fields. A matching document is reused, while a different score or payload produces a collision and leaves the original unchanged. This also gives the collision a useful meaning: the same identity cannot represent two different completed rounds. The phone test proved same-ID server retrieval for suffix `cVa3QX`, but I did not run the deployed G02 mismatched-score experiment. Therefore, I can explain and reference the collision code without falsely calling G02 passed. Replay is different because it intentionally starts a new quiz and receives a new ID.

### 4. Cloud trust

I use Firebase Authentication and Firestore rules to prove who owns an attempt and whether its fields follow the required schema. Those controls do not prove the user answered the questions honestly. A modified client could still send any in-range `correctCount`, because the rules cannot see the original questions and selected answers. For stronger trust, I would move scoring to an authenticated backend endpoint. The server would create a round, store or reference the correct answers privately, and issue an expiring random nonce. The client would submit its selections with that nonce and one idempotency key. The server would verify the Firebase identity, reject expired or reused rounds, calculate the score itself, and atomically create the final attempt. A repeated identical request would return the original result, while a different payload using the same key would become a collision. This design would make the server authoritative for scoring. It would still need rate limiting, logging, monitoring, and protection against automated clients, account sharing, stolen sessions, and server compromise. Ownership rules are necessary, but I do not confuse them with trusted scoring.

### 5. Critique of the AI proposal

I asked OpenAI Codex on November 16, 2026: “Using a fictional six-field score schema, design recovery when a Flutter cloud write commits but its acknowledgement is lost. Avoid credentials.” The useful short recommendation was: “Keep one idempotency key and reconcile with a server read.” I tested two important claims from that idea. First, keeping one round ID allowed the app to find the same attempt after restart. Second, a direct server read resolved the result without replaying the quiz. The proposal was helpful but incomplete. A generic answer can forget that Firestore may run a transaction callback multiple times, so UI changes, counters, random IDs, and unrelated network calls must remain outside that callback. It can also forget stale responses after authentication changes, server timestamp resolution, pending-write metadata, or the difference between save failure and verification failure. I revised the design by freezing the payload, comparing existing fixed fields, guarding responses with `initiatingUid` and `initiatingRound`, and requiring `Source.server`. I also recorded that G01–G03 were not executed instead of treating design reasoning as test evidence.

### 6. Personal design defense

I intentionally made answer feedback understandable without relying on color alone. A correct answer displays a check icon, green styling, and the words “Correct ✓.” An incorrect answer displays a cancel icon and text naming the correct answer. This helps users who cannot easily distinguish red and green and also makes screenshots readable. Screenshot `03_correct_double_tap.png` shows this cue after the answer became locked. For cloud work, I show separate messages for submitting, verifying, unknown, permission denied, unavailable verification, and verified success. I chose user-triggered recovery instead of an endless automatic loop because automatic retries can waste quota, hide a persistent problem, and make duplicate-risk reasoning harder. The trade-off is that the user must press a recovery button and wait. My failed-first test found a controller-lifecycle assertion during the restart lookup, recorded in `08_failed_first_restart_lookup.png`. I removed the premature disposal, reran analysis and tests, rebuilt the APK, and repeated T07. Screenshot `09_restart_server_verified.png` shows the corrected server-only lookup succeeding with a redacted round suffix.

## Graduate analyses

### 1. G01/G02 transaction interleavings

I designed G01 around two authenticated clients using the same UID, round ID, and frozen payload. Both clients may enter their transaction callbacks and initially read an absent document. Firestore cannot commit both independent creations as if they happened at the same time. After one client commits, Firestore retries or re-evaluates the competing transaction against the newer document state. My callback then reads the existing attempt and compares the five non-timestamp fields. If they match, the second client accepts the existing document and both clients can verify the same server record. The result should be exactly one document, not two. In G02, the sequence begins similarly, but the second client carries a different score. The comparison fails, the repository reports a collision, and it never calls `set` over the original. This preserves immutability even under contention. I also keep UI work and random ID generation outside the callback because Firestore may rerun it. I did not complete the required two-client deployed experiment, so G01 and G02 remain “Not run” in my table. My explanation describes the implemented interleaving and expected result, not fabricated proof. A future run should correlate both clients with the same redacted suffix and a console timestamp.

### 2. Server-authoritative scoring

I would improve scoring by introducing an authenticated API instead of trusting the phone’s `correctCount`. First, the client would request a new round. The server would authenticate the Firebase ID token, choose questions, keep the answers private, and return the public questions with a random round nonce and expiration time. After play, the client would send its selected answer identifiers, the nonce, and an idempotency key. The server would check the user, nonce, expiry, question set, and whether that key was already used. It would calculate the score from server-held answers and atomically create the immutable result. If the same request arrived again, the API would return the original response. If the same key arrived with a different payload, it would report a collision. The nonce would be marked consumed to block replay. I would also add rate limits, structured audit logs, App Check where appropriate, and alerts for abuse. Residual threats would remain: users can share accounts, automate the public client, steal authenticated sessions, or exploit a server bug. Administrators or a compromised backend could also alter data. Server authority greatly improves score integrity, but it does not eliminate identity fraud or operational security risks.

### 3. Transaction versus backend idempotency endpoint

I chose a direct Firestore transaction because it has low conceptual and operational overhead for this class assignment. The phone talks directly to Firestore, Firebase Authentication supplies the UID, and security rules enforce ownership and schema. For normal use, this removes an extra API hop and avoids hosting another service. The disadvantages are that transaction callbacks may retry under contention, clients need careful recovery logic, and rules can validate only the submitted shape—not honest scoring. Reads and retries also count toward Firestore usage. A backend idempotency endpoint adds network latency, deployment work, monitoring, and compute cost. However, it centralizes scoring, replay protection, collision policy, auditing, and error mapping. It can keep correct answers secret and return the same stored result for a repeated idempotency key. Under heavy contention, the backend can coordinate requests consistently instead of placing all retry reasoning in every client version. My G01/G02 design shows why both approaches still need one stable identity and atomic create-once behavior. I did not collect deployed concurrency measurements, so I cannot claim measured latency or contention results. For this assignment I prefer the transaction for simplicity; for a competitive or graded production quiz, I would accept the endpoint’s extra cost for authoritative correctness and better auditing.

## Redacted cloud proof and restart instructions

- Redacted round suffix: `cVa3QX`
- Safe app proof: `09_restart_server_verified.png` displays “Cloud verified prior round …cVa3QX.”
- The raw T06 screenshot is intentionally excluded because it contains the full UID and document ID.
- Firestore Console screenshot: Not captured during the automated phone session; add a redacted console screenshot before final submission if time permits.
- Authorized grader procedure: obtain User A credentials through the instructor-approved private channel, sign in, select the search icon, enter the privately supplied full round ID and expected score 2, and press “Read server.” The app performs `GetOptions(source: Source.server)` and shows the redacted suffix on success.
- No passwords, access tokens, or service-account credentials appear in this document.

## Final reproducibility checklist

- [x] `flutter analyze` reports no issues.
- [x] `flutter test` passes.
- [x] Release APK builds and was installed on the Samsung phone.
- [x] Rules were deployed to `ica16-a-mustufa`.
- [x] Real deployed write and server-only reads passed for suffix `cVa3QX`.
- [x] Repository is public and final commit is `86d4eef`.
- [x] Six core responses and three graduate analyses are included.
- [ ] T03 and T08–T12 still need complete observed records.
- [ ] G01–G03 still need deployed two-client/stale-response records.
- [ ] A redacted Firestore Console screenshot should be added before final submission.

