# iOS Signing and Release

> **Current status:** release configuration is fail-closed and TestFlight upload
> has no implementation in the release workflow. The iOS and backend release
> branches contain account-bound StoreKit remediation, but neither branch is
> production evidence: the backend change is not deployed and the App Store
> subscription catalog is incomplete. No production identifier was inferred or
> invented. D-01, a signed authorization artifact, deployment proof,
> and live App Store/StoreKit proof remain required before upload may be enabled.

## Configuration ownership

Only the `ChapterFlow` app target consumes application service configuration.
Extension targets do not reference these xcconfigs and therefore do not inherit
API, Cognito, Sentry, StoreKit, or provenance values.

| Layer | Purpose |
|---|---|
| `Config/Base.xcconfig` | Shared app-target keys and safe empty/disabled defaults. |
| `Config/Debug.xcconfig` | Debug environment; includes Base and optional local override. |
| `Config/Staging.xcconfig` | Explicit Staging environment with Release-like compiler settings. |
| `Config/Release.xcconfig` | Production environment; includes Base and validated generated override. |
| `Secrets.xcconfig` | Optional, gitignored final override for the app target only. |
| `Secrets.example.xcconfig` | Empty documentation template; never a Release input. |

The project and every target declare Debug, Staging, and Release. The app target
points those configurations to `Debug.xcconfig`, `Staging.xcconfig`, and
`Release.xcconfig`; extension/test Staging configurations clone their existing
Release settings without an app xcconfig reference. `#include?` makes
`Secrets.xcconfig` optional, so clean checkouts and PR builds do not manufacture
placeholder values.

For local integration only:

```sh
cp Secrets.example.xcconfig Secrets.xcconfig
# Fill the gitignored file. Escape URL separators as https:/$()/host/path.
```

Do not share or upload `Secrets.xcconfig`.

## Fail-closed release tools

The entry point is `scripts/release-config/release_config.py`:

```sh
python3 scripts/release-config/release_config.py validate
python3 scripts/release-config/release_config.py generate \
  --xcconfig Secrets.xcconfig \
  --manifest "$TMPDIR/ChapterFlowReleaseManifest.json"
python3 scripts/release-config/release_config.py inspect-archive \
  --archive "$TMPDIR/ChapterFlow.xcarchive" \
  --manifest "$TMPDIR/ChapterFlowReleaseManifest.json"
python3 scripts/release-config/release_config.py inspect-app \
  --app "$TMPDIR/ipa-inspection/Payload/ChapterFlow.app" \
  --manifest "$TMPDIR/ChapterFlowReleaseManifest.json"
```

The validator emits only stable issue codes such as
`E_APP_STORE_URL_ID_MISMATCH`; it never prints input values. Validation rejects:

- empty, unexpanded, template, or placeholder values;
- non-HTTPS production API/support URLs;
- malformed Cognito region, pool, client, or domain;
- any app bundle other than `com.chapterflow.ios`;
- missing/non-numeric App Store ID, invalid App Store URL, or ID/URL mismatch;
- missing, malformed, duplicate, or non-approved StoreKit product IDs;
- absent Sentry policy or enabled Sentry without a valid HTTPS DSN;
- absent/malformed version, build number, full commit SHA, or Release configuration;
- absent/malformed Team ID, App Store Connect key/issuer/private key, distribution
  certificate, or certificate password.
- backend Apple App ID that is missing, malformed, or differs from both the
  protected `APP_STORE_ID` and `Config/ApprovedReleaseIdentity.json`.

Monthly and annual StoreKit products are required, and together they must exactly
match `APPROVED_STOREKIT_PRODUCT_IDS`. `SK_ANNUAL_UPFRONT_PRODUCT_ID`
must remain empty: the audited backend verification route currently requires a
subscription expiry and cannot safely authorize a non-renewing upfront product.
The validator rejects a nonempty value until backend support and route tests land.

`generate` first runs the same validation, then writes:

1. gitignored `Secrets.xcconfig`, mode `0600`, containing build-time app values;
2. a schema-versioned nonsecret JSON manifest with identifiers, backend Apple
   App ID attestation, build provenance, signing-validation state, and a SHA-256
   fingerprint.

The manifest never contains Sentry DSN, `.p8`, `.p12`, certificate password, JWT,
or other credential material. Its contract is documented by
`Config/ReleaseManifest.schema.json`; `ReleaseManifest.template.json` is a
non-runnable shape reference with required markers.

The archive and exported-app inspectors compare the generated manifest with the
built `Info.plist`, including bundle, API/Cognito configuration, App Store
destination, StoreKit IDs, Sentry policy, configuration, version, build, commit,
and manifest fingerprint. They reject unexpanded/template strings before export
or artifact publication.

Run the deterministic failure-injection suite locally with:

```sh
bash scripts/tests/test-release-config.sh
```

The same suite and an unsigned Release build run on every PR.

The hosted `macos-26` PR job keeps its general build, snapshot, and UI gates on
the newest installed Xcode 26. The dedicated local StoreKit contract selects
`/Applications/Xcode_26.2.app/Contents/Developer` when that hosted toolchain is
present and pins its simulator to iOS 26.2, the last verified pairing for local
StoreKit configurations. If the hosted image drifts, the lane attempts Apple's
runtime downloader once and then fails closed; it never falls back to the live
App Store Connect catalog or silently skips the exact purchase/restore test.

Runtime validation emits `app_configuration_validated` at most once per app
process with allowlisted readiness booleans. After validation, internal and
verified TestFlight diagnostics may retain the configured and successfully
loaded StoreKit product IDs plus coarse verifier health. Those identifiers are
the same nonsecret values in the release manifest; no transaction, account,
receipt, JWS, token, or response body is retained.

The affected synchronous launch work has a host regression guard: 25 complete
production-configuration validations must finish within the 250 ms main-thread
stall budget. A fresh Xcode 26 host run on 2026-07-11 completed the batch in
16 ms. This is not a substitute for the required signed-device cold-launch
trace; the 1.5 s physical-device launch proof remains a release stop condition.

## Account-bound StoreKit lifecycle

The native client derives StoreKit's `appAccountToken` from the authenticated
Cognito `sub`, which must be an RFC UUID. Account binding is replaced
synchronously during authentication transitions and cleared before a signed-out
state is exposed. Direct purchases and win-back purchases include that token.

Before calling the backend or finishing a transaction, the StoreKit boundary
requires a configured product, direct purchased ownership, and an active account.
A nonempty signed token must match the active account exactly. A tokenless legacy
transaction is delegated to the backend only; it can be processed only when the
backend already has a same-account reverse mapping. Local subscription, refund,
and win-back discovery is filtered to matching tokens or those backend-authorized
legacy transaction IDs so StoreKit state cannot leak across ChapterFlow accounts.

The backend response is authoritative and additive. The client finishes only an
acknowledgement with `ok: true`, `processed: true`, and a recognized
`transactionState` (`active`, `expired`, or `revoked`). Purchase success requires
an active authoritative Pro entitlement, but its source may remain a
higher-priority admin, promotion, gift, license, or other backend grant; the
client never rewrites that source to Apple. Processed terminal transactions and
processed active transactions that do not leave Pro authoritative are finished
without granting access locally. Old or unknown acknowledgement shapes fail
closed and remain unfinished for a later retry.

Every entitlement refresh, foreground refresh, and restore replays unfinished
transactions. This permits a transaction rejected under the wrong ChapterFlow
account to succeed when its bound account returns. Offer-code redemption is not
shown on the free paywall because Apple's sheet cannot attach an
`appAccountToken`; it is available from subscription management only for an
account already mapped to an Apple subscription.

## App Store Connect inventory

A signed-in inspection on 2026-07-11 established the following owner-controlled
values and readiness state. The monthly product shell was then created with the
owner-approved product identifier and duration. Its United States base price was
confirmed at `$7.99` per month, with Apple's automatic equivalent prices applied
to the other storefronts. Availability and customer-facing metadata remain
unset:

| Item | Observed value/state |
|---|---|
| App name/version | ChapterFlow; iOS 1.0 is Prepare for Submission. |
| Native bundle ID | `com.chapterflow.ios`. |
| App Apple ID | `6787864558`. |
| Apple Developer Team ID | `ZG3C9QBA8Z` (confirmed from the existing production SSM identity parameter). |
| Subscription group | ChapterFlow Pro; group ID `22211821`. |
| Existing recurring product | `com.chapterflow.pro.annual`; Apple product ID `6787866553`; one year. |
| Annual readiness | Missing Metadata; United States price `$44.99` per year and Canada price `$59.99` per year exist across 175 territories; English (Canada) localization exists; availability remains unset. |
| Monthly recurring product | `com.chapterflow.pro.monthly`; Apple product ID `6789951571`; one month. |
| Monthly readiness | Missing Metadata; United States base price `$7.99` per month with Apple's automatic storefront equivalents; availability/localization/review metadata are not set. |
| Subscription levels | Annual and monthly are both level 1 in App Store Connect, matching their equivalent Pro access. |
| Family Sharing | Off for both subscriptions, matching the client/backend rejection policy. |
| Server Notifications V2 | Production and Sandbox URLs are both unset. |
| Other in-app purchases | None. |

The canonical destination derived from the confirmed app identity is
`https://apps.apple.com/app/id6787864558`, but the listing is not yet a live
storefront proof. The release catalog must not use the old local StoreKit IDs or
the backend's previous defaults as evidence. Before release, an owner must fully
configure both recurring products' metadata/pricing/availability, attach the
first subscriptions to version 1.0, and configure the Production and Sandbox App
Store Server Notifications V2 URLs. The checked-in StoreKit Test fixture uses
the observed United States annual price of `$44.99`; it does not replace the
remaining App Store Connect metadata and availability evidence.

## Protected release inputs

Production GitHub **environment secrets only**:

Do not define these as repository- or organization-scoped Actions secrets. An
older tagged commit executes its historical workflow, so broadly scoped legacy
credentials could make an old upload path reachable. Before this branch merges,
the release owner must remove or rotate every repository/organization-scoped
App Store Connect and distribution credential, then provision the replacement
only in the reviewer-protected `production` Environment. Until that external
control is evidenced, all `v*` tag creation and release workflow execution must
remain disabled in repository settings.

| Name | Purpose |
|---|---|
| `RELEASE_API_BASE_URL` | Approved production HTTPS API base URL. |
| `RELEASE_COGNITO_REGION` | Production Cognito region. |
| `RELEASE_COGNITO_USER_POOL_ID` | Production user-pool ID. |
| `RELEASE_COGNITO_CLIENT_ID` | Native app client ID. |
| `RELEASE_COGNITO_DOMAIN` | Hosted/custom Cognito domain without scheme/path. |
| `SENTRY_DSN` | Required only when `SENTRY_POLICY=enabled`. |
| `APPLE_TEAM_ID` | Ten-character Apple team identifier. |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID. |
| `ASC_API_KEY_P8` | Full private-key contents. |
| `DISTRIBUTION_CERT_P12_BASE64` | Distribution certificate export, base64 encoded. |
| `DISTRIBUTION_CERT_PASSWORD` | Password for the `.p12`. |

Protected GitHub **environment variables**:

| Name | Purpose |
|---|---|
| `APP_STORE_ID` | Exact numeric ChapterFlow App Store ID. |
| `APP_STORE_URL` | Exact `https://apps.apple.com/.../id<APP_STORE_ID>` destination. |
| `SUPPORT_URL` | Live HTTPS support route. |
| `APPROVED_STOREKIT_PRODUCT_IDS` | Owner-approved comma-separated product allowlist. |
| `SK_MONTHLY_PRODUCT_ID` | Selected monthly product. |
| `SK_ANNUAL_PRODUCT_ID` | Selected annual product. |
| `SK_ANNUAL_UPFRONT_PRODUCT_ID` | Reserved; must remain empty until backend support exists. |
| `SENTRY_POLICY` | Exactly `disabled` or `enabled`. |

Backend attestation variables, also protected by the production environment:

| Name | Required assertion |
|---|---|
| `BACKEND_DEPLOYMENT_COMMIT_SHA` | Full deployed backend commit SHA. |
| `BACKEND_ATTESTATION_ID` | Owner-approved ADR/change/evidence identifier. |
| `BACKEND_ATTESTATION_APPROVED` | Exactly `true`. |
| `BACKEND_APPLE_BUNDLE_ID` | Must equal the iOS bundle identifier. |
| `BACKEND_APPLE_APP_ID` | Must exactly equal `APP_STORE_ID` and the approved ChapterFlow Apple App ID. |
| `BACKEND_VERIFICATION_PRODUCT_ALLOWLIST` | Must exactly match the mobile approved product set. |
| `BACKEND_MOBILE_CONFIG_APP_STORE_URL` | Must exactly match `APP_STORE_URL`. |
| `BACKEND_APPLE_ENVIRONMENT` | Exactly `Production`. |
| `BACKEND_SUBSCRIPTION_GROUP_ID` | Approved App Store subscription group. |
| `BACKEND_PRODUCT_ALLOWLIST_ENFORCED` | Exactly `true`. |
| `BACKEND_APPLE_ENVIRONMENT_ENFORCED` | Exactly `true`. |
| `BACKEND_SUBSCRIPTION_GROUP_ENFORCED` | Exactly `true`. |
| `BACKEND_ACCOUNT_BINDING_ENFORCED` | Exactly `true` only after a verified Apple transaction is bound to the authenticated account (for example with `appAccountToken`) and cross-account replay tests pass. |

These values attest to evidence; they do not authorize upload or make the backend
safe. A production reviewer may approve them only after backend route tests and
deployed runtime evidence prove the assertions. The release-branch backend source
adds exact IAP bundle, product allowlist, environment, subscription-group,
ownership, and initiating-account enforcement; the release manifest separately
attests the exact Apple App ID without creating a new runtime authority flag.
Production still runs the earlier backend and therefore does not satisfy those
assertions. Upload remains blocked until the reviewed backend is merged,
configured with owner-approved values, deployed, and independently attested.

Use a protected GitHub Environment with required reviewers for all release
inputs. Enable prevent-self-review and restrict deployment branches/tags to
protected `main` release refs. Protect `v*` tags from deletion or creation by
unreviewed actors. Product IDs and URLs are nonsecret, but protection prevents
unreviewed release changes. The workflow also requires the requested SHA to be
exactly the fetched `origin/main` tip; an older main ancestor is rejected.
Repository settings and environment-only credentials remain mandatory because
a historical commit runs its historical workflow, not the current file.

## Release workflow order — archive-only safe scaffold

`.github/workflows/release.yml` binds archive validation to the protected GitHub
Environment named `production`. It prepares an inspected artifact but cannot upload it:

1. Checkout the requested immutable SHA and derive version/build/commit.
2. Run the release-config failure-injection suite.
3. Validate all D-01, backend-attestation, and signing inputs.
4. Generate gitignored xcconfig and nonsecret manifest.
5. Bind backend attestation into the manifest fingerprint and app provenance.
6. Run strict SwiftLint, focused CoreKit/Paywall tests, and unsigned Release build.
7. Install signing material only after all earlier gates pass.
8. Create the signed archive with the same version/build/commit.
9. Inspect the archive against the manifest, verify its code signature, lint its
   built plist, and prove the executable is readable by `otool`.
10. Export the IPA, require exactly one payload app, and repeat manifest, plist,
    code-signature, executable, signing-team, and provisioning-identity checks on
    the final exported app.
11. Stage only the inspected IPA, nonsecret manifest, and SHA-256 sidecar in a
    clean directory; immediately verify the sidecar against the staged IPA.
12. Remove the private key, certificate file, temporary keychain, and generated
    xcconfig before the pinned artifact action executes.
13. Retain the clean three-file artifact and its digest for 30 days.
14. Fail explicitly with `E_TESTFLIGHT_UPLOAD_NOT_AUTHORIZED`; no TestFlight
    upload job or upload command exists in this workflow.

Missing D-01 data fails before key installation or archive creation. The workflow
does not copy `Secrets.example.xcconfig`, synthesize product IDs, silently skip
a requested release, or upload directly from the archive job. A requested
release remains red after producing its archive artifact so a skipped upload
cannot be mistaken for success.

Tag releases derive marketing version from `v<version>`. Manual releases require
the `marketing_version` input. Build number currently uses the GitHub workflow
run number as a traceable positive value; WP-REL-03 retains ownership of the
final organization-wide version/build policy.

The workflow is the only supported production archive path. There is currently
no supported production upload path. A direct local
`xcodebuild archive` remains possible for developer diagnostics, but it is not
release-qualified and must not be exported or uploaded: it bypasses protected
inputs, retained provenance, archive inspection, and the dependent upload gate.

## Signing setup

Create an App Store Connect API key under **Users and Access → Integrations** and
store its key ID, issuer ID, and downloaded `.p8` in the protected environment.
Create an Apple Distribution certificate in Xcode, export its certificate and
private key as password-protected `.p12`, then encode it without committing it:

```sh
base64 -i Certificates.p12 | pbcopy
```

The workflow imports it into a temporary keychain and deletes that keychain,
the decoded `.p12`, the generated xcconfig, and the App Store Connect key in an
`always()` cleanup step.

## Pending external proof and release stop conditions

The infrastructure is intentionally not proof that external services are ready.
Do not enable upload until an owner has reviewed the exact production manifest and all
of the following are demonstrated on the resulting signed archive/TestFlight build:

- repository/organization-scoped legacy Apple signing and upload credentials
  have been removed or rotated, and replacements are production-Environment-only;
- the App Store ID/URL opens the exact ChapterFlow listing in supported storefronts;
- every configured StoreKit product exists, is approved/available, and the backend
  grants entitlement only for the same allowlist;
- entitlement cache/listener state is namespaced to the authenticated subject,
  cleared on sign-out, and cannot survive an account switch;
- API and Cognito identifiers match the production backend and signed app;
- certificate, provisioning, associated-domain, SIWA, APNs, and Keychain
  capabilities pass their signed-device matrix;
- Sentry policy/DSN and privacy disclosure match actual runtime behavior;
- an independently signed, expiring authorization binds the exact iOS SHA,
  deployed backend SHA, environment identities, backend controls, and IPA digest;
- a separately controlled first upload and TestFlight processing exercise completes.

At the time of this document update, the isolated source branches enforce the
account-bound contract and cover delayed, tokenless-legacy, cross-account,
terminal, refund, replay, account-session ABA, and coalesced delivery cases. The
deployed production backend is still the pre-remediation build and its
`/book/config/ios` response still lacks the exact listing URL. App Store Connect
confirms the app/bundle/group and both recurring product shells above, but neither
subscription is sale-ready and notification URLs are unset. Those live Apple and
backend proofs remain pending. Mutable GitHub
variables and an unkeyed manifest fingerprint are consistency checks, not
authorization. A green source build or archive must not be represented as a
successful production release.

## Health gate and rollback trigger

The first release uses zero-tolerance gates during internal and TestFlight
validation:

- every successful launch emits exactly one validated-configuration diagnostic;
- both approved recurring product IDs load in every supported storefront sample;
- controlled purchase and restore exercises record a healthy verifier and an
  authoritative backend Pro entitlement;
- the exact App Store listing and support fallback both open on the device matrix;
- no configuration failure, unknown product, cross-account claim, secret scan,
  or archive/manifest mismatch is accepted.

Any violation stops rollout and leaves upload disabled. If a fault is found
after a future production enablement, operations must first disable remote hard
gates/soft nudges, stop the release workflow, and revert to the last inspected
artifact only after its manifest is revalidated. Billing access must never be
restored through a client-side entitlement fallback.
