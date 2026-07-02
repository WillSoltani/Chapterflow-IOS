# iOS Signing & Release

> **Status:** Authored and ready. Live uploads are deferred until Apple Developer Program enrollment. The signing and TestFlight workflows are fully implemented and secret-guarded — they no-op cleanly when secrets are absent.

---

## Table of contents

1. [Overview](#overview)
2. [Required GitHub secrets](#required-github-secrets)
3. [Generating the App Store Connect API key](#generating-the-app-store-connect-api-key)
4. [Exporting the distribution certificate (.p12)](#exporting-the-distribution-certificate-p12)
5. [Triggering a TestFlight upload](#triggering-a-testflight-upload)
6. [Branch protection & required status checks](#branch-protection--required-status-checks)
7. [Contract-drift monitoring](#contract-drift-monitoring)

---

## Overview

The CI system has three workflows:

| Workflow | File | Trigger | Gating secret |
|---|---|---|---|
| **PR — Build, Test & Lint** | `.github/workflows/pr.yml` | Every PR + push to `main` | None (always runs) |
| **Release — Archive & TestFlight** | `.github/workflows/release.yml` | Tag push `v*` or manual dispatch | `ASC_KEY_ID` |
| **Contract Drift** | `.github/workflows/contract-drift.yml` | Weekly (Sunday 02:00 UTC) or manual | `CF_CI_TOKEN` |

The PR workflow is the **required merge gate**. The release and drift workflows are inert until secrets are configured.

---

## Required GitHub secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** for each:

### PR workflow (no secrets needed)

The build/test/lint workflow requires no secrets. It uses placeholder values from `Secrets.example.xcconfig`.

### Release workflow — TestFlight upload

| Secret name | Where to get it |
|---|---|
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → key ID (8-character string) |
| `ASC_ISSUER_ID` | Same page — "Issuer ID" (UUID string) |
| `ASC_API_KEY_P8` | The **full contents** of the downloaded `.p8` file (including `-----BEGIN EC PRIVATE KEY-----` header/footer) |
| `APPLE_TEAM_ID` | Developer portal → Membership → Team ID (10-character alphanumeric string) |
| `DISTRIBUTION_CERT_P12_BASE64` | See [Exporting the distribution certificate](#exporting-the-distribution-certificate-p12) |
| `DISTRIBUTION_CERT_PASSWORD` | Password you chose when exporting the `.p12` |

### Drift workflow (optional)

| Secret name | Description |
|---|---|
| `CF_CI_TOKEN` | A valid Cognito `id_token` for a dedicated CI test account. Rotate before it expires (or use a long-lived custom authorizer token). |
| `CF_API_BASE_URL` | Live API base URL (e.g. `https://api.chapterflow.com`) |
| `CF_TEST_BOOK_ID` | ID of a seeded book in the CI test account (default: `b-atomic-habits`) |
| `CF_TEST_CHAPTER_N` | Chapter number to fetch (default: `1`) |

---

## Generating the App Store Connect API key

1. Log into [App Store Connect](https://appstoreconnect.apple.com).
2. Navigate to **Users and Access → Integrations → App Store Connect API**.
3. Click **+** to generate a new key.
   - Name: `ChapterFlow CI`
   - Access: **App Manager** (minimum required for uploads; use Admin only if needed)
4. Download the `.p8` file **immediately** — Apple only lets you download it once.
5. Note the **Key ID** and **Issuer ID** shown on the same page.
6. Add `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_API_KEY_P8` as GitHub secrets (see table above).

---

## Exporting the distribution certificate (.p12)

You need a **Apple Distribution** (or **iOS Distribution**) certificate to sign Release builds.

### First-time: create via Xcode

1. Open Xcode → **Settings → Accounts** → select your Apple ID.
2. Click **Manage Certificates** → **+** → **Apple Distribution**.
3. Xcode creates the certificate + private key in your Keychain.

### Export from Keychain Access

1. Open **Keychain Access** → **My Certificates**.
2. Find **Apple Distribution: Your Name (TEAMID)**.
3. Right-click → **Export** → choose `.p12` format.
4. Set a strong password (you will need this as `DISTRIBUTION_CERT_PASSWORD`).
5. Encode as base64:
   ```sh
   base64 -i Certificates.p12 | pbcopy
   ```
6. Paste the result as the `DISTRIBUTION_CERT_P12_BASE64` secret.

---

## Triggering a TestFlight upload

### Via a version tag (recommended)

```sh
git tag v1.0.0
git push origin v1.0.0
```

The `release.yml` workflow starts automatically. Monitor progress at **Actions → Release — Archive & TestFlight**.

### Via manual dispatch

Go to **Actions → Release — Archive & TestFlight → Run workflow**. Optionally fill in "What to Test" notes.

### Post-upload steps

After the workflow uploads the build:

1. Log into [App Store Connect](https://appstoreconnect.apple.com).
2. Navigate to your app → **TestFlight**.
3. The build appears under **iOS Builds** (may take 5–30 min to process).
4. Add testers and submit for Beta App Review if required.

> **⚠️ DEFERRED:** The live TestFlight upload has not been verified because Apple Developer Program enrollment is pending. Run the above steps after enrollment and confirm the upload completes successfully.

---

## Branch protection & required status checks

After pushing the PR workflow, configure branch protection to gate merges:

1. Go to **Settings → Branches → Add rule** for `main`.
2. Enable:
   - **Require status checks to pass before merging**
   - **Require branches to be up to date before merging**
3. Add these checks (type the exact job name from `.github/workflows/pr.yml`):
   - `Build & Test`
   - `Lint`
4. Enable **Require pull request reviews before merging** (recommended: 1 review).
5. Enable **Do not allow bypassing the above settings** to prevent force-pushing around CI.

---

## Contract-drift monitoring

The **Contract Drift** workflow runs weekly and validates that live API responses still decode correctly with the current `Codable` models.

### Activating the drift check

1. Create a dedicated ChapterFlow test account (do not use a personal account).
2. Obtain a Cognito `id_token` for that account (sign in via the app or directly via the Cognito `InitiateAuth` API).
3. Add it as `CF_CI_TOKEN` in repository secrets.
4. Add `CF_API_BASE_URL` pointing to the live API.
5. Optionally set `CF_TEST_BOOK_ID` / `CF_TEST_CHAPTER_N` for the book/chapter used in fixture fetches.

### Token rotation

Cognito `id_token`s expire in 1 hour. For CI, use one of:

- A **refresh token** flow: run `InitiateAuth` with `REFRESH_TOKEN_AUTH` before each drift run (requires storing the refresh token as a secret — also expires eventually).
- A **long-lived service account token** from a custom Lambda authorizer endpoint (recommended for production CI).

### Running locally

```sh
CF_CI_TOKEN=<token> API_BASE_URL=https://api.chapterflow.com \
  bash scripts/refresh-fixtures.sh

swift test --package-path Packages/Models --filter "Evolution"
swift test --package-path Packages/Fixtures
```
