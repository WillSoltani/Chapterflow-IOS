// SocialFeature — Profile, pairs, gifts, reflections, share cards, and referrals.
//
// Key entry points:
//   ProfileView           — own-profile tab (display name, avatar, tier, stats, cosmetics, badges)
//   PublicProfileView     — read-only partner profile
//   SocialRepository      — single async data layer for all of Lane S
//   LiveSocialRepository  — production network implementation
//   FakeSocialRepository  — in-memory fake for tests and previews
