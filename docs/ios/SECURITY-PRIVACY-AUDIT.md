# P10.13 — Security & Privacy-Manifest Review

**Status: ✅ SIGNED OFF** · Branch `feat/p10-13` · Pre-submission audit (feeds P10.7's App Privacy label).

This is the final security + privacy audit before App Store submission. Findings
are reported **by reference** (`file:line`); no secret value, `.p8` content, or
private-key block appears in this document or in git.

---

## 1. Privacy manifests (`PrivacyInfo.xcprivacy`)

A manifest ships in **every** shipping binary — the main app and all five
extensions. Each is a well-formed plist (`plutil -lint` passes).

| Target | File | Tracking | Collected data | Required-reason APIs |
|---|---|---|---|---|
| ChapterFlow (app) | `ChapterFlow/PrivacyInfo.xcprivacy` | none | email, name, user ID, purchases, other user content, product interaction, crash/perf/other diagnostics | UserDefaults `CA92.1`, `1C8F.1` |
| ChapterflowWidgets | `ChapterflowWidgets/PrivacyInfo.xcprivacy` | none | — (read-only display) | UserDefaults `1C8F.1` |
| ShareExtension | `ShareExtension/PrivacyInfo.xcprivacy` | none | — (writes App-Group outbox) | UserDefaults `1C8F.1` |
| ActionExtension | `ActionExtension/PrivacyInfo.xcprivacy` | none | — (writes App-Group outbox) | UserDefaults `1C8F.1` |
| NotificationService | `NotificationService/PrivacyInfo.xcprivacy` | none | — | none |
| NotificationContent | `NotificationContent/PrivacyInfo.xcprivacy` | none | — | none |

**Wiring.** The main app uses an Xcode file-system-synchronized root group
(`ChapterFlow/`), so its manifest is auto-included as a bundle resource with no
project edit. The five classic extension targets are wired into their
**Resources** build phase (never Compile Sources) by
`scripts/add_privacy_manifests.rb` via the `xcodeproj` Ruby gem — `project.pbxproj`
is never hand-edited. The script is idempotent.

### Required-reason APIs — why these reasons

- **UserDefaults** (`NSPrivacyAccessedAPICategoryUserDefaults`) is the only
  required-reason category the app's own code touches.
  - `CA92.1` — the app reads/writes its own defaults (e.g. app-lock, last-seen
    version).
  - `1C8F.1` — the app **and** the widget/share/action extensions read/write the
    shared `group.com.chapterflow` App-Group defaults (widget snapshot state,
    extension outbox). Extensions declare only `1C8F.1`.
- **Not used** (verified by source scan — nothing to declare): file-timestamp
  APIs (only file **size** via `.fileSizeKey` / `attributesOfItem[.size]`, which
  is not a required-reason category), system-boot-time APIs, disk-space APIs,
  active-keyboard APIs.

---

## 2. App Privacy "nutrition label" ↔ actual data flows

The label (owned by **P10.7**) must match the manifest above. Actual flows:

| Data | Where it goes | Linked to identity | Purpose | Tracking |
|---|---|---|---|---|
| Email address | AWS Cognito / REST API (account) | yes | App Functionality | no |
| Name / display name | REST API (profile) | yes | App Functionality | no |
| User ID (Cognito subject) | REST API; Sentry (crash correlation) | yes | App Functionality | no |
| Purchase history (sub status) | REST API (StoreKit → backend) | yes | App Functionality | no |
| Other user content (notebook, highlights, "Ask", social) | REST API | yes | App Functionality | no |
| Product interaction (funnel events, no PII) | REST API analytics beacon | yes | Analytics, App Functionality | no |
| Crash / performance / other diagnostics | Sentry | yes | App Functionality | no |

**No tracking anywhere:** there is no `AdSupport`/IDFA, no
`AppTrackingTransparency` prompt, and no data shared for cross-app/cross-site
tracking. `NSPrivacyTracking = false` and `NSPrivacyTrackingDomains` is empty in
every manifest (source scan for `ASIdentifierManager` / `ATTrackingManager` /
`advertisingIdentifier`: **0 hits**).

Diagnostics are marked **linked** because `SentryCrashReporter.setUser(id:)`
attaches the account user ID to reports (`Packages/CoreKit/Sources/CoreKit/Crash/SentryCrashReporter.swift:28`),
even though `sendDefaultPii = false` and PII is scrubbed.

---

## 3. Secrets — none in bundle or history

- `Secrets.xcconfig` is **gitignored** (`git check-ignore` → tracked ignore) and
  **never committed** — only `Secrets.example.xcconfig` (placeholders only) is in
  the tree.
- Config values reach the bundle as build-time substitutions
  (`Config/Info.plist` → `CoreKit.AppConfig`); the `.xcconfig` itself is not
  bundled.
- Git history scan (`git log --all -p`) for private-key blocks, `AKIA…` AWS keys,
  `xox…` / `sk_live_…` tokens, and Sentry-DSN-shaped URLs: **no secret values**.
  The single `-----BEGIN … PRIVATE KEY-----` string match is documentation prose
  in `docs/ios/SIGNING-AND-RELEASE.md` describing the `ASC_API_KEY_P8` CI
  variable — not a key value.
- No `.p8` / `.pem` / `.mobileprovision` / private-key file was ever added to git.

---

## 4. Transport security (ATS)

- **No** `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` key anywhere —
  `Config/Info.plist`, all extension `Info.plist`s, `project.pbxproj`, and Swift
  sources (scan: **0 hits**). ATS is at its secure default.
- `API_BASE_URL` is **HTTPS** (verified in `Secrets.xcconfig`; value not printed).
  All backend/S3/Cognito traffic is TLS.

---

## 5. Token storage (Keychain)

- Tokens live in the Keychain via
  `Packages/Persistence/Sources/Persistence/Keychain.swift` and `TokenStore.swift`.
- Accessibility is **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** by
  default (`Keychain.swift:31,47,100`) — matches the runbook: survives background
  refresh after first unlock, never syncs off-device.
- Asserted by test `PersistenceTests.swift:26` ("default configuration uses
  afterFirstUnlockThisDeviceOnly").

---

## 6. Logs are PII-free

- `Networking/RequestLogger.swift` — `DebugRequestLogger` is **`#if DEBUG`**-only
  (no request logging in Release); it logs method/URL/status only and **never**
  the `Authorization` header or bodies.
- `CoreKit/Crash/CrashReporter.swift:85` — `PIIScrubber` redacts email addresses
  and `Bearer <token>` from any string/dictionary before it reaches a sink;
  applied at breadcrumb construction and again in Sentry's `beforeSend`.
- Sentry: `sendDefaultPii = false` (`SentryCrashReporter.swift:19`).
- Analytics event properties (`AnalyticsEvent.swift`) carry IDs/counts only — no
  email, name, or free text.

---

## 7. Third-party SDK privacy manifests

Both required SDKs ship their own `PrivacyInfo.xcprivacy` (Apple aggregates them
with the app's):

- **Sentry** (`sentry-cocoa` 8.58.3) — declares CrashData / PerformanceData /
  OtherDiagnosticData and UserDefaults `CA92.1`, SystemBootTime `35F9.1`,
  FileTimestamp `C617.1`.
- **Amplify** (`amplify-swift` 2.58.4) — ships manifests across its modules
  (16 `*.xcprivacy` files; umbrella `Amplify/Resources/PrivacyInfo.xcprivacy`
  present).

---

## 8. Dependency / license check

31 resolved SPM dependencies (app-level `Package.resolved`). All licenses are
**permissive and App-Store-compatible** — no copyleft (GPL/LGPL/MPL):

- **MIT:** `SQLite.swift`, `sentry-cocoa`.
- **Apache-2.0:** everything else — `amplify-swift`, `aws-sdk-swift`,
  `aws-crt-swift`, `smithy-swift`, `async-http-client`, and the Apple Swift
  ecosystem (`swift-nio*`, `swift-crypto`, `swift-certificates`, `swift-asn1`,
  `swift-collections`, `swift-algorithms`, `swift-log`, `swift-http-types`, …).

No package pins to an unstable branch/revision; all pin to released versions.

---

## Sign-off checklist

- [x] Privacy manifest present in app + all 5 extensions; validates (`plutil -lint`).
- [x] Required-reason APIs declared (UserDefaults `CA92.1`/`1C8F.1`); none missing.
- [x] App Privacy label data types match actual flows (§2) — feeds P10.7.
- [x] `NSPrivacyTracking = false`, empty tracking domains; no IDFA/ATT in code.
- [x] No secrets/keys in the bundle or git history; `Secrets.xcconfig` gitignored.
- [x] ATS clean — no arbitrary-loads exception; base URL is HTTPS.
- [x] Tokens in Keychain with `afterFirstUnlockThisDeviceOnly` (test-asserted).
- [x] Logs PII-free (Release logging off; email/Bearer scrubbed; Sentry PII off).
- [x] Third-party manifests present (Amplify **and** Sentry).
- [x] Dependency/license check clean (permissive licenses only).
- [x] App-target build succeeds with manifests wired.
