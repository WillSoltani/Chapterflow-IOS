# Reconciliation spec — one clean `main` (foundation + unified AuthKit)

> **Paste this whole file to Claude in Xcode as a single task.** It works on the branch
> **`chore/reconcile-integration`** (already created + pushed). Do not start a new worktree — check that
> branch out and work on it.

## Role & context
You are a senior iOS engineer on ChapterFlow (Swift 6, SwiftUI, iOS 18+, Apple-Pro bar). Read `CLAUDE.md`
and `docs/PLAN.md`. **Do not stop until the whole workspace builds and all tests pass, then merge to `main`.**

**Why this task exists:** the P0/P1 prompts were each built on their own branch off an empty `main` and
never merged between prompts, so the branches diverged — no single branch has all the finished work, and
the two "integration" branches carry stubs where feature branches have the real code. This task assembles
ONE coherent, building `main`.

**Starting point (already done for you on `chore/reconcile-integration`):**
- Base = `chore/int-1` — the most-integrated branch: full DesignSystem, CoreKit, Networking, AppFeature
  (themed 5-tab shell + deep links), and an AuthKit that currently does **Sign-in-with-Apple only** +
  `SessionManager` + token refresh + app-lock + step-up reauth (manual `CognitoTokenClient`, no Amplify).
- `Packages/Persistence` has been **replaced with `feat/p0-4`'s full version** (`Keychain`, `TokenStore`,
  `SwiftDataStack`, `FileStore`, `KeyValueStore`, `AppPreferences`) — int-1 only had a lean stub.

## Goal (Definition of Done)
`chore/reconcile-integration` builds green (app + every package) and passes tests, with:
1. Full foundation intact (DesignSystem, CoreKit, Networking, **full Persistence**, AppFeature).
2. **One coherent AuthKit** offering **BOTH** email/password (Amplify) **AND** Sign in with Apple, on top of
   the existing `SessionManager` (token refresh + BGTask pre-refresh + app-lock + step-up reauth) and
   identity bootstrap. A single token store, a single `AuthState`, a single Welcome entry point.
3. AuthKit wired into AppFeature so the app launches → resolves session → routes to auth or the shell.
Then it becomes `main` (see "Land it").

## Do these in order

### 1) Fix Persistence integration (build the base first)
`Packages/Persistence` was swapped to `feat/p0-4`'s version; some int-1 code may reference the old lean API.
Build the workspace and resolve any Persistence reference breaks. Decide the **single token store**: use
`Persistence.TokenStore` (Keychain-backed) as the app-wide token store and **delete AuthKit's duplicate
`KeychainTokenStore.swift`**, repointing `SessionManager` at `Persistence.TokenStore`. Get the base green
BEFORE touching auth further.

### 2) Bring in the email/password auth from `feat/p1-3`
Pull these files (they don't exist on the base — additive):
```
for f in AuthComponents AuthFlowModel AuthService AuthTokenProvider UserSummary PreviewAuthService \
         WelcomeView SignUpView LogInView VerifyEmailView ForgotPasswordView; do
  git checkout origin/feat/p1-3 -- "Packages/AuthKit/Sources/AuthKit/$f.swift"
done
git checkout origin/feat/p1-3 -- Packages/AuthKit/Tests/AuthKitTests/AuthFlowModelTests.swift \
                                  Packages/AuthKit/Tests/AuthKitTests/TokenRefreshTests.swift
```
Then **add the Amplify dependency** to `Packages/AuthKit/Package.swift` (compare with
`git show origin/feat/p1-3:Packages/AuthKit/Package.swift` — it declares `aws-amplify/amplify-swift`,
products `Amplify` + `AWSCognitoAuthPlugin`). Amplify is the token engine for SRP email/password.

### 3) Reconcile AuthKit into one coherent package (the core work)
Make these the single, non-duplicated design:
- **Token layer = Amplify.** `AuthService` (from feat/p1-3, Amplify) is the auth engine: `signUp`,
  `confirmSignUp`, `resendCode`, `signIn`, `signOut`, `forgotPassword`, `confirmForgotPassword`, plus
  `signInWithApple`. Configure Amplify against the `COGNITO_*` in `AppConfig` (Region `us-east-1`, pool
  `us-east-1_VCBEQWMgD`, client `6iik2mf6cbsncngvk96fjoutec` — public/no-secret, SRP-enabled; a custom
  Cognito domain `auth.chapterflow.ca` is available for Hosted-UI if needed).
- **One `AuthState`** and **one `SessionManager`.** Reconcile int-1's `AuthState`/`SessionManager`/
  `TokenRefreshing`/`SessionManager+BGTask`/`AppLockManager`/`ReauthView`/`AppLockView` with feat/p1-3's
  `AuthFlowModel`/`AuthTokenProvider`. Keep int-1's session lifecycle (refresh, BGTask pre-refresh,
  app-lock, step-up reauth) but drive it off Amplify's session (`Amplify.Auth.fetchAuthSession` for the
  current `id_token`) instead of the manual `CognitoTokenClient`. Remove `CognitoTokenClient.swift` if it's
  no longer needed (its Apple-code-exchange is replaced by Amplify Apple sign-in) — or keep it only if you
  route native SIWA through it; don't leave two token paths.
- **One Welcome entry point.** Merge int-1's SIWA `AuthFlowView` with feat/p1-3's `WelcomeView` into a
  single Welcome that offers **Continue with Apple** AND **Sign up / Log in with email**, navigating to the
  feat/p1-3 screens (`SignUp` → `VerifyEmail`, `LogIn`, `ForgotPassword`). Delete whichever of the two
  original welcome views you don't keep.
- **`TokenProviding` for Networking:** expose one implementation (reuse `AuthTokenProvider` or int-1's) that
  returns the current Amplify `id_token` and refreshes it; wire that single instance into the `APIClient`
  (in AppFeature's `Dependencies`). The web API accepts it as `Authorization: Bearer`.
- Delete duplicate/dead files so there is exactly one of each concept. Keep/merge the tests
  (`AuthFlowModelTests`, `TokenRefreshTests`, `AuthKitTests`) so they compile and pass.

### 4) Sanity-check the other foundation packages are the best versions
The base took DesignSystem/CoreKit/Networking/AppFeature from int-1. Quickly diff against the dedicated
branches and pull anything int-1's integration simplified or dropped:
```
git diff --stat origin/chore/reconcile-integration origin/feat/p0-2 -- Packages/DesignSystem
git diff --stat origin/chore/reconcile-integration origin/feat/p0-5 -- Packages/CoreKit
git diff --stat origin/chore/reconcile-integration origin/feat/p0-3 -- Packages/Networking
git diff --stat origin/chore/reconcile-integration origin/feat/p0-6 -- Packages/AppFeature
```
If a dedicated branch clearly has a more complete/correct version of ITS package, prefer it, then re-build.
(Expect int-1's to usually win for CoreKit/Networking/AppFeature; DesignSystem may be more complete on
`feat/p0-2` — verify.)

### 5) Wire auth into the app (identity bootstrap)
In AppFeature: on launch, configure Amplify, resolve the session, hydrate a `UserProfile` (via
`GET /auth/session` + `GET /me`), and route to the reconciled `AuthFlow` (signed-out) or the `MainTabView`
(signed-in). Ensure the app actually uses the reconciled AuthKit, not a placeholder.

### 6) Build green + verify
- `xcodebuild -scheme ChapterFlow -destination 'platform=iOS Simulator,name=iPhone 16' build` and
  `... test` — both green; SPM resolves Amplify; SwiftLint clean; every `#Preview` renders.
- Manually confirm in the Simulator (pointing at `API_BASE_URL` = local dev, `npm run dev` running): the app
  launches → Welcome shows both Apple + email/password → you can create an account / log in against the real
  Cognito pool (auth hits AWS directly regardless of the localhost API) → land on the shell.

## Land it
When green: commit, push `chore/reconcile-integration`, open a PR **→ `main`**, and merge it — this becomes
the real `main`. Then **close the now-superseded PRs #1–#10** (their work is folded in here) and delete
their branches. Leave a short PR description listing what was reconciled from which branch.

## Guardrails
- One concept = one file/type. No duplicate `AuthState`, token store, or Welcome view left behind.
- Do not regress the foundation (keep the themed shell + deep links + full Persistence).
- Server is truth for gating; the client never fabricates unlocks (per PLAN §3).
- If a piece genuinely conflicts and you must choose, prefer the plan-aligned one (email/password primary,
  Amplify token layer) and note the choice in the PR.
