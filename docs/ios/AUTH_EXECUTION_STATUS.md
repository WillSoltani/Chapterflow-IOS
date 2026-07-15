# Authentication Execution Status

## WP-AUTH-01A — Authoritative Cognito Session Identity and Apple Fail-Closed Boundary

Status: **implementation, bounded review remediation, latest-main verification, and final local validation complete; publication, exact-head CI, and merge are pending**.

This record covers the bounded `WP-AUTH-01A` development slice. It does not certify Sign in with Apple, a deployed backend, signed capabilities, or release readiness.

## Execution identity

| Field | Value |
|---|---|
| Starting iOS revision | `c6009cf2a4839bb46b78998d7eec92f42ec66bab` |
| Branch | `codex/wp-auth-01a-session-identity` |
| Isolated worktree | `/private/tmp/Chapterflow-IOS-wp-auth-01a` |
| Backend source revision inspected read-only | `6a792cf2572f585e56ce5dbb181307955c1896a8` |
| Backend evidence type | Static source inspection only |
| Deployed backend revision | **Unverified** |
| Backend runtime probe | **Not run** |
| PR / merge / final-main revision | **Pending** |

The worktree was created from the prerequisite-verified iOS revision above. The user's primary checkout and frozen PR `#117` are outside this work package and must remain untouched.

## Scope and outcome under implementation

The current worktree removes the ability to publish a production signed-in state from an empty, fallback, or token-mirror-only identity. Email sign-in, restoration, and refresh are being routed through the same Amplify/Cognito session evidence, with `SessionManager` as the sole app lifecycle authority and production token-mirror writer.

The former native Apple authorization-code exchange is not being replaced with another custom session mechanism. Its method now fails with a stable typed provider-unavailable error, and the Apple action is absent from the production auth UI until `WP-AUTH-01B` proves a supported, restorable provider flow.

This slice intentionally does not create `SessionScope`, perform account teardown, implement account deletion, change networking policy, change endpoint contracts, modify persistence schemas, add entitlements, configure Cognito, mutate backend source, deploy anything, or perform release work.

## Authoritative session architecture

### Ownership

| Component | Responsibility | Explicit non-responsibility |
|---|---|---|
| `AmplifyCognitoSessionClient` | Wrap the installed Amplify operations for sign-in, session fetch, current-user lookup, and sign-out; return immutable app-owned snapshots. | Does not publish app state or write the token mirror. |
| `AuthService` | Prove one `VerifiedSession` from a signed-in Amplify session, Cognito tokens, ID-token `sub`, and Amplify current-user identity. | Does not own `AuthState`, emit a parallel event stream, or save tokens. |
| `SessionIdentity` | Hold the validated stable Cognito subject plus optional display metadata and source. | Username, email, and display name are not authority keys. |
| `SessionManager` | Own `AuthState`, `currentIdentity`, session generation, restoration, sign-in commits, refresh single-flight, step-up waiters, sign-out, and token-mirror reconciliation. | Does not construct account-private repositories; that remains `WP-ID-01`. |
| `TokenStore` | Cache the most recently verified Cognito token bundle in Keychain for authorized consumers. | Stored tokens are not independent proof of login and cannot restore `AuthState` by themselves. |

### Identity proof

A production `SessionIdentity` is constructed only when all of the following agree:

1. Amplify reports an active signed-in Cognito user-pool session.
2. The session exposes a Cognito token bundle through the supported token provider.
3. The Amplify-returned ID token is structurally a three-part JWT with a finite, positive, numeric `exp` claim.
4. That expiry is still in the future and agrees with `StoredTokens.expiresAt` to within one second; no invented default expiry is accepted.
5. The ID token parses to a nonempty `sub`.
6. Amplify returns the current user.
7. The current user's stable ID exactly matches the ID-token `sub`.

The expiry checks are consistency evidence on credentials supplied by the authoritative Amplify session; they are not a second client-owned token verifier. Missing, nonnumeric, expired, or mirror-inconsistent expiry evidence fails closed.

`SessionIdentity` is immutable, `Sendable`, and `Equatable`. Construction rejects empty or whitespace-only subjects and the sentinel values `anon` and `local`. Optional username/email values are display metadata only. Auth identity, auth state, provider errors, verified sessions, and stored tokens use redacted descriptions and reflection.

The only synthetic identity is the fixed Debug UI-test subject `uitest-user-123`. It is available only when all three existing hermetic boundaries are active together:

- `CF_UITEST_BYPASS_AUTH=1`
- `CF_STUB_SERVER=1`
- `CF_HERMETIC_TEST_CONFIGURATION=1`

That bypass does not seed or read Keychain. The fake JWT, synthetic identity, activation predicate, and establishment method are all enclosed by `#if DEBUG`, so those values and entry points are absent from non-Debug compilation.

### Sign-in result fidelity

The Cognito seam preserves the Amplify sign-in next step instead of flattening every incomplete sign-in into one result. `.signedIn` proceeds to full session verification, `.resetPassword` becomes actionable reset-password guidance without creating a session, and every other incomplete challenge becomes an explicit additional-step-required failure. No incomplete next step can write the mirror or publish signed-in.

### State transitions

| Starting state | Trigger | Required evidence / guard | Resulting state | Token-mirror effect |
|---|---|---|---|---|
| `unknown` | Production configuration and restoration start | Configured Amplify client; generation-tagged task | Remains `unknown` while resolving | Existing mirror is not treated as authentication. |
| `unknown` | Restoration succeeds | Signed-in Amplify session, token bundle, valid `sub`, matching current user | `signedIn(identity)` | Save the verified bundle before publishing signed-in. |
| `unknown` | Restoration is signed out, malformed, inconsistent, or fails | No acceptable verified session | `signedOut` | Sign out the provider and delete the mirror when the generation is still current. |
| `signedOut` | Email sign-in succeeds | Amplify sign-in plus the same verification used by restoration | `signedIn(identity)` | Save only the verified bundle, then publish signed-in. |
| `signedOut` | Email sign-in requires password reset | Cognito next step is `.resetPassword` | Remains `signedOut` with actionable guidance | Clear any stale mirror; never publish partial success. |
| `signedOut` | Explicit sign-out begins while provider sign-in is in flight | Generation changes immediately; the owned sign-in flight must settle before provider sign-out | `unknown` until Amplify sign-out truth is known | The stale sign-in cannot commit; provider sign-out runs after it settles so relaunch cannot restore the late session. |
| Any prior session | New sign-in/restoration generation begins | Generation increment | `signedOut` for sign-in or `unknown` for restoration | Old restoration, refresh, and step-up work is cancelled/invalidated. |
| `signedIn(identity)` | Synchronous token requested and cached token is current | Cached ID-token `sub` matches `identity.subject` | `signedIn(identity)` | `currentIdToken()` returns the token only on a subject match; corruption or cross-account mismatch returns `nil`. |
| `signedIn(identity)` | Throwing/corrupt mirror is encountered by `validToken()` | Authoritative refresh returns a verified session for the same identity | `signedIn(same identity)` | Replace the unreadable mirror with the newly verified bundle. |
| `signedIn(identity)` or `reconnecting` | Proactive or reactive refresh succeeds | One shared flight; same generation, subject, and identity source | Identity is preserved; `reconnecting` returns to `signedIn(identity)` | Save once, then resume every active waiter with the same result. |
| `signedIn(identity)` | Refresh is cancelled or fails transiently | Failure is not an unrecoverable authentication failure | `signedIn(same identity)` | Preserve the current mirror; deliver the cancellation/transient error without signing out. |
| `signedIn(identity)` or `reauthRequired` | Refresh proves an unrecoverable auth failure or inconsistent identity | Current flight/generation still applies | `signedOut` | Begin a new generation, clear identity and mirror, drain refresh/step-up waiters, and clear the invalid provider session. |
| `signedIn(identity)` | Verifier is temporarily unavailable | Existing authoritative identity remains active | `reconnecting` | No new identity is created. |
| `reconnecting` | Recovery is acknowledged | Existing authoritative identity still present | `signedIn(identity)` | No authority change. |
| `signedIn(identity)` | Step-up requested | Existing identity required | `reauthRequired` | No identity or token replacement. |
| `reauthRequired` | Internal, generation-bound step-up proof completes | Every waiter matches the current generation and exact identity | `signedIn(same identity)` | Waiters resume once. The current UI does not synthesize this proof. |
| `reauthRequired` | Cancel / “Sign In Again” | Explicit sign-out lifecycle | Waiters fail once; state follows the two explicit sign-out outcomes below | Mirror handling follows provider-local sign-out truth. |
| Any authoritative state | Explicit sign-out starts | New generation invalidates restoration/refresh and drains step-up waiters | `unknown` while Amplify attempts to clear its local session | Retain the mirror until local sign-out truth is known. |
| `unknown` during explicit sign-out | Amplify reports `.signedOutLocally` | Completion still belongs to the current generation | `signedOut` | Delete the mirror, then publish signed-out success. |
| `unknown` during explicit sign-out | Amplify reports `.failedLocally` | Completion still belongs to the current generation | Restore `signedIn(previous identity)` when one existed | Preserve the prior mirror and return failure; never claim signed-out success. |
| Any state | Stale restoration/refresh/step-up completion | Generation, flight ID, or identity no longer matches | No state mutation | Cannot repopulate the mirror or resurrect signed-in. |

### Refresh and step-up coordination

Provider sign-in is also an owned, generation-bound single flight. A second sign-in cannot start concurrently. Explicit sign-out invalidates the app generation immediately but waits for any provider-mutating sign-in call to settle before clearing Amplify; the stale caller receives cancellation and cannot write the mirror. This ordering prevents an Amplify sign-in completion from recreating a restorable provider session after sign-out has already reported success.

The current refresh coordinator stores one generation- and identity-bound flight. Concurrent proactive expiry checks and reactive refresh callers join that flight as individually cancellable waiters. Cancelling one waiter resumes only that waiter; the underlying task is cancelled only after the last waiter leaves. Completion clears the flight, checks the current generation and subject again, saves one token bundle, and resumes the remaining continuations exactly once.

Starting a newer session generation or signing out removes the flight before cancelling its task and resumes its waiters with an authentication failure. A completion from the removed flight therefore has no handle through which it can mutate the newer session.

Refresh failures are classified before teardown. Cancellation and transient failures such as offline delivery resume callers with the original error while preserving the authoritative identity and mirror. Only an unrecoverable authentication failure, inconsistent refreshed identity, or failed mirror commit enters the fail-closed path. That path starts a new generation, clears local authority and the mirror, drains both refresh and step-up waiters, and asks Amplify to clear the invalid local provider session; it does not restore identity when provider cleanup itself cannot be confirmed because the preceding session evidence is already invalid.

Step-up follows the same generation and identity discipline. It cannot start without an authoritative identity. All successful waiters retain that exact identity; cancellation and sign-out fail waiters once. The former UI password/biometric placeholders have been removed because neither produced Cognito step-up proof. The current recovery surface attempts explicit sign-out and opens normal sign-in only after local provider sign-out is confirmed; a failed local sign-out restores the prior authoritative identity instead of displaying false success.

Explicit user sign-out has deliberately different semantics from fail-closed invalidation. It captures the prior verified identity, invalidates outstanding work, presents `unknown` while Amplify clears its local Cognito session, and retains the mirror during that attempt. Only `AWSCognitoSignOutResult.signedOutLocally == true` permits mirror deletion and `signedOut`. If local sign-out fails, `SessionManager.signOut()` returns `false`, restores the prior authoritative identity, keeps its mirror, and never exposes a false signed-out success.

## TokenStore reconciliation and compatibility

- Amplify/Cognito session truth is authoritative; `TokenStore` is a mirror.
- A populated mirror with no active Amplify session starts signed out and cannot authenticate the UI.
- Sign-in, restoration, and refresh update the mirror only after identity verification.
- Explicit sign-out clears the mirror only after Amplify confirms `.signedOutLocally`; failed local sign-out preserves the previous authoritative identity and mirror.
- Invalid restoration or unrecoverable refresh clears local authority and the mirror immediately, because invalid session evidence cannot be restored as signed-in merely because provider cleanup fails.
- `TokenStoring.load()` now throws; undecodable Keychain data becomes `PersistenceError.invalidTokenData` instead of being silently treated as a valid or empty session.
- `validToken()` repairs a throwing/corrupt mirror through the shared authoritative refresh flight; it does not treat a decode failure as authentication truth or force a transient sign-out.
- `currentIdToken()` returns a synchronous mirror token only when its JWT `sub` matches `currentIdentity.subject`; corruption, missing data, or a cross-account token returns `nil` without exposure.
- The stored JSON token shape and Keychain configuration are unchanged. There is no persistence-schema migration in this slice.
- The `AuthState.signedIn` payload changes from a display-oriented user summary to validated `SessionIdentity`; dependent app composition is adapted to consume the shared `SessionManager`.

## Apple decision for WP-AUTH-01A

### Decision

Apple sign-in is **fail-closed and hidden in WP-AUTH-01A**.

The installed SDK is Amplify Swift `2.58.4`, revision `478bcc9cd98a9d372f47d1b89fdd8d3efffe7e46`. Amplify documents a supported provider web-UI API, including `signInWithWebUI(for: .apple, presentationAnchor:)`, and its managed user-pool session can be fetched and refreshed through the same Amplify Auth category used by email sign-in. Relevant official references:

- [Set up Amplify Auth sign-in with web UI](https://docs.amplify.aws/swift/frontend/auth/web-ui-sign-in/)
- [Manage Amplify Auth user sessions](https://docs.amplify.aws/swift/frontend/auth/manage-user-sessions/)
- [Amplify Swift `AuthProvider`](https://aws-amplify.github.io/amplify-swift/docs/Enums/AuthProvider.html)

SDK API availability is not deployment proof. The current iOS configuration supplies a user pool, app client, region, and `USER_SRP_AUTH`, but no hosted-UI OAuth domain, scopes, callback URI, or logout URI. `Config/ChapterFlow.entitlements` does not contain the Sign in with Apple entitlement. No signed provisioning, provider configuration, deployed callback allowlist, account-link migration, or physical-device restoration evidence was available in this slice.

Accordingly:

- the manual native authorization-code-to-Cognito-token exchange is removed as a success path;
- `AuthService.signInWithApple` returns `AuthProviderError.unavailable(.apple)` without calling a token endpoint or writing the mirror;
- the Apple control and handler are removed from the production auth flow, so there is no dead or misleading button;
- email/password remains available through the authoritative session path;
- the old manual exchange must not be restored as a rollback.

### Backend source findings at `6a792cf2572f585e56ce5dbb181307955c1896a8`

These findings are static source observations, not claims about any deployed environment:

1. `apple-token-store.ts` defines `putAppleRefreshToken`, and `docs/ios/APPLE-AUTH.md` says a native exchange persists the Apple refresh token through it. A tree-wide symbol search found only that definition and documentation reference—no route or production caller that performs the claimed native exchange and subject-bound write.
2. The standard GitHub deployment workflows do not reference `APPLE_ISSUER_ID`, `APPLE_BUNDLE_ID`, `APPLE_KEY_ID`, or `APPLE_PRIVATE_KEY`. Source can resolve those values, but their protected injection and deployed presence were not proven.
3. `APPLE_ISSUER_ID` has contradictory meanings in current source documentation: SIWA/revocation code requires a 10-character Apple Developer Team ID, while StoreKit/App Store Server documentation and `apple-env.ts` describe an App Store Connect issuer UUID. A single value cannot safely satisfy both contracts.
4. The Cognito PreSignUp linker logs raw verified email and destination username in `apple_link_skip`, `apple_link_failed`, and `apple_link_ok` fields. Those are PII/identity values and must be removed or irreversibly transformed before production use.
5. A PreSignUp linking Lambda exists in source, but the user pool is external to CDK and the repository documentation requires one-time manual `LambdaConfig` wiring. There is no deployed proof that the trigger, Apple IdP, app-client provider list, attribute mapping, IAM, alarms, or callback/logout configuration is active.
6. The migration for users/accounts created or represented by the former manual iOS flow is undefined. Source does not prove how an existing native account, an Apple federated account, a relay/hidden-email account, a duplicate subject, and any private data or entitlement lineage converge without a split account.

## WP-AUTH-01B prerequisite checklist

Apple must remain unavailable until every applicable item below has evidence. Source completion without deployed and signed-device proof is insufficient.

### Architecture and configuration

- [ ] Keep playbook decision `D-03` option A: one supported Cognito/Amplify session for email and Apple. Do not add a second iOS token/refresh state machine or inject externally exchanged tokens into Amplify internals.
- [ ] Select and document the single supported Amplify entry point, expected redirect lifecycle, cancellation behavior, and restoration path for the exact pinned SDK.
- [ ] Configure a nonproduction Cognito Apple IdP with the approved Services ID/client ID, Apple Developer Team ID, Key ID, private key, and verified attribute mappings.
- [ ] Add `SignInWithApple` to the correct Cognito app client's supported identity providers.
- [ ] Configure and verify the Cognito hosted-UI domain, allowed callback URI, allowed logout URI, OAuth scopes, response/grant settings, and the matching iOS Amplify configuration.
- [ ] Prove state/PKCE/redirect validation through the supported SDK flow; do not implement an app-owned OAuth parser or token endpoint exchange.
- [ ] Define one availability gate so the Apple UI is exposed only when the complete supported configuration is present and validated.

### Secrets and deployment

- [ ] Split ambiguous Apple credentials into purpose-specific names and validation. In particular, do not reuse `APPLE_ISSUER_ID` for both the SIWA Team ID and the App Store Connect issuer UUID; separate SIWA and App Store Connect key/issuer contracts even if an operator later chooses related keys.
- [ ] Wire each required nonsecret identifier and protected secret through the approved GitHub Environment/SSM/CDK/Lambda path without logging it.
- [ ] Add fail-closed deployment validation for missing, malformed, or semantically incompatible Apple/Cognito settings.
- [ ] Capture the exact deployed backend revision and sanitized effective configuration evidence. Do not infer deployment from backend `main`.

### Account linking and migration

- [ ] Wire the PreSignUp trigger to the intended external Cognito pool while preserving every existing `LambdaConfig` field; prove the function ARN, scoped IAM, invoke permission, error alarm, and exact pool/app-client target.
- [ ] Remove raw email, destination username, Apple subject, Cognito subject, and other identity values from linking diagnostics. Retain only allowlisted categorical markers/reasons and nonidentifying correlation data.
- [ ] Test linking only from verified provider evidence and a unique verified destination. Define explicit outcomes for hidden email, private relay, absent email, unverified email, ambiguous matches, already-federated destinations, and provider/link failures.
- [ ] Inventory legacy manual-flow users and possible duplicate/split Cognito identities without exporting PII into task evidence.
- [ ] Approve a subject-preserving migration/link plan for native email accounts, existing Apple federated accounts, duplicate subjects, private data, and entitlement lineage before enabling Apple.
- [ ] Force safe sign-out and supported Amplify reauthentication for legacy local token mirrors. Never translate or inject the old token bundle into a new Amplify session.
- [ ] Define an operator-supported conflict path for cases that cannot be linked automatically. No email-only or client-side merge may grant access to another account.

### Revocation and account lifecycle

- [ ] Reconcile the supported hosted/federated session with Apple token-revocation obligations. Cognito hosted UI does not expose Apple's refresh token to the app/backend in the current documented path.
- [ ] If Apple refresh-token retention remains required, design a backend-owned, subject-bound, encrypted capture route that is compatible with the authoritative Cognito session and does not become an alternate iOS login authority.
- [ ] Add and test the missing production caller for `putAppleRefreshToken`, or remove the inaccurate contract if the approved provider flow cannot supply that token. A documentation statement alone is not an implementation.
- [ ] Prove Apple credential revocation, Cognito global sign-out, backend account lifecycle behavior, and recoverable operational handling without weakening deletion truthfulness.

### iOS capability and signed proof

- [ ] Add the Sign in with Apple capability/entitlement only under a separately approved signed-capability task, with the correct App ID, provisioning profile, bundle identifier, and environments.
- [ ] Restore the system Apple control only after availability is proven; preserve its native accessibility behavior and keep cancellation non-erroring.
- [ ] On a signed physical device against the approved nonproduction environment, verify first Apple sign-in, repeat sign-in, cancellation, relay/hidden email, app relaunch, forced token refresh, background/foreground, offline recovery, revocation, sign-out, and account switch.
- [ ] Prove that email and Apple reach the same `SessionManager`, restore through Amplify, preserve one stable Cognito subject, and cannot create two active session authorities.
- [ ] Run two-account tests demonstrating no private-data or entitlement crossover. Coordinate the full account-scoped repository lifecycle with `WP-ID-01`; do not create it opportunistically in `WP-AUTH-01B`.
- [ ] Record exact device/OS/build/revision, sanitized runtime evidence, focused tests, CI checks, and rollback. Do not use TestFlight or production without separate owner authorization.

## Tests-first and validation record

Tests were introduced before the implementation. The first focused AuthKit run failed on the intended defects:

- stored tokens alone could create a signed-in state with an empty identity;
- step-up completion could synthesize an empty identity;
- `validToken()` trusted the token mirror without an authoritative session;
- eight concurrent refresh callers invoked more than one underlying refresh.

The expanded lifecycle suite then produced the expected compile-red state because the planned `SessionIdentity`, Cognito client seam, and generation-bound APIs did not yet exist. Those failures are tests-first evidence, not final validation.

The fixed-checklist independent review found one P1 and one P2: a provider sign-in could settle after explicit sign-out and remain restorable, and `CognitoUserSnapshot` exposed identity through synthesized reflection. Both regression tests failed against the reviewed implementation. The single bounded remediation introduced an owned sign-in flight with provider-operation serialization and full snapshot redaction. The same reviewer re-inspected only those corrections and returned **CLEAR**, with no remaining P0/P1/P2 finding.

Freshly fetched `origin/main` remained exactly `c6009cf2a4839bb46b78998d7eec92f42ec66bab`, matching the worktree base, so latest-main integration was a verified no-op. The following checks then passed on the corrected tree:

| Validation | Current status |
|---|---|
| `swift test --package-path Packages/AuthKit` | **Passed — 65 tests in 10 suites** |
| `swift test --package-path Packages/Persistence` | **Passed — 104 tests in 31 suites** |
| `swift test --package-path Packages/AppFeature` | **Passed — 87 tests in 19 suites** |
| Focused `SignInFlowTests` on iPhone 17 Pro simulator, iOS 26.5 | **Passed — 10 passed / 0 failed / 0 skipped** |
| Unsigned Debug simulator app build | **Passed** |
| `scripts/verify-wp-dev-01-compile-boundaries.sh` | **Passed** |
| `swiftlint lint --strict --reporter github-actions-logging` | **Passed — 0 violations / 763 Swift files** |
| Fast native contract semantics | **Passed — 83 operations / 93 producers / 29 matrix rows / 93 relations** |
| Independent bounded final auth review | **Passed after one remediation — initial 1 P1 / 1 P2; re-review CLEAR with no remaining P0/P1/P2** |
| Latest-main integration | **Passed — fetched `origin/main`; exact same base SHA, no-op** |
| Final-revision focused reruns | **Passed** |
| Targeted documentation whitespace check | **Passed — no whitespace errors** |
| Final whole-worktree `git diff --check` | **Passed** |
| Exact-head PR CI and post-merge `main` CI | **Pending** |

No live Cognito, Apple, Keychain-entitlement, signed-device, TestFlight, or production-service validation has been performed or claimed by this record.

## Compatibility, rollback, and deferred work

No backend endpoint, auth envelope, networking policy, Keychain access group, persistence schema, or production configuration changes in WP-AUTH-01A. The intentional source compatibility changes are the validated `AuthState.signedIn(SessionIdentity)` payload, the throwing `TokenStoring.load()`, and auth views receiving the shared session manager.

Before merge, rollback is deletion of this isolated branch/worktree only. After merge, any source rollback must preserve the Apple fail-closed boundary: revert the session-core change selectively or ship a focused correction, but never restore the former manual token exchange or expose the Apple control without the `WP-AUTH-01B` gates above. The stored token encoding is unchanged, so no data migration rollback is required.

Deferred work is limited to `WP-AUTH-01B` provider/configuration/linking/revocation/signed-device proof and the later `WP-ID-01` account-scoped repository lifecycle. Backend mutation, runtime probing, entitlement expansion, signing, deployment, release, App Store, and TestFlight work were not performed in this slice.
