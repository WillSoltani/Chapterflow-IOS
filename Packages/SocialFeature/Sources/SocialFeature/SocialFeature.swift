// SocialFeature — Profile, pairs, gifts, reflections, share cards, referrals, and safety.
//
// Key entry points:
//   ProfileView             — own-profile tab (display name, avatar, tier, stats, cosmetics, badges)
//   PublicProfileView       — read-only partner profile (with block/report menu, P7.7)
//   PairsView               — reading partners list (invite, accept, nudge, unpair)
//   PairDetailView          — partner progress + nudge/unpair actions
//   InvitePairView          — generate & share invite link
//   AcceptInviteView        — manual code-entry fallback (critical: iOS has no deferred deep linking)
//   PairingConsentView      — explicit consent step required before pairing (Apple Guideline 1.2, P7.7)
//   BlockConfirmationView   — block-user confirmation with consequences explained (P7.7)
//   ReportView              — reason picker + code-of-conduct note for moderation reports (P7.7)
//   SafetyMenuButton        — toolbar menu exposing block/report actions on public profiles (P7.7)
//   NudgeRateLimiter        — client-side per-partner nudge cap (3/24 h); server is authoritative (P7.7)
//   SocialRepository        — single async data layer for all of Lane S (incl. safety methods, P7.7)
//   LiveSocialRepository    — production network implementation
//   FakeSocialRepository    — in-memory fake for tests and previews
