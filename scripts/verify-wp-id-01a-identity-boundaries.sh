#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

reject_pattern() {
  local label="$1"
  local pattern="$2"
  shift 2

  local matches
  matches="$(rg -n --glob '*.swift' "$pattern" "$@" || true)"
  if [[ -n "$matches" ]]; then
    echo "ERROR: $label"
    echo "$matches"
    failures=$((failures + 1))
  else
    echo "PASS: $label"
  fi
}

require_pattern() {
  local label="$1"
  local pattern="$2"
  shift 2

  if rg -q --glob '*.swift' "$pattern" "$@"; then
    echo "PASS: $label"
  else
    echo "ERROR: $label"
    failures=$((failures + 1))
  fi
}

if [[ -e "$repo_root/Packages/AppFeature/Sources/AppFeature/UserIdBox.swift" ]]; then
  echo "ERROR: mutable UserIdBox identity bridge still exists"
  failures=$((failures + 1))
else
  echo "PASS: mutable UserIdBox identity bridge is absent"
fi

reject_pattern \
  "production code has no UserIdBox references" \
  'UserIdBox' \
  "$repo_root/Packages"

reject_pattern \
  "production repositories have no mutable identity-provider closures" \
  '@Sendable[[:space:]]*\(\)[[:space:]]*->[[:space:]]*String\?' \
  "$repo_root/Packages"

reject_pattern \
  "reader, quiz, and AI code has no anonymous or local identity fallback" \
  '(userId\(\)[[:space:]]*\?\?[[:space:]]*"anon"|userId:[[:space:]]*String[[:space:]]*=[[:space:]]*"local")' \
  "$repo_root/Packages/ReaderFeature" \
  "$repo_root/Packages/QuizFeature" \
  "$repo_root/Packages/AIFeature"

require_pattern \
  "private API clients acquire tokens through immutable account authority" \
  'AccountBoundSessionTokenProvider' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/SessionScope.swift"

require_pattern \
  "root private UI requires the active scope to match current identity" \
  'hasActiveMatchingSessionScope' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppRootView.swift"

require_pattern \
  "paywall factories use the session graph API client" \
  'apiClient:[[:space:]]*graph[.]apiClient' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel.swift"

reject_pattern \
  "paywall factories never use a process-mutable API client" \
  'apiClient:[[:space:]]*apiClient' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel.swift"

reject_pattern \
  "ownerless App Group commands and minutes are never deleted" \
  'removeObject' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+AudioControl.swift" \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+P89.swift"

reject_pattern \
  "ownerless App Group artifacts are not applied to the active account" \
  '(activeAudioPlayerModel|handle\(deepLink:|SharedStateReader\(\)\.load\(\)|SharedStateWriter\.shared\.publish)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+AudioControl.swift" \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+P89.swift"

reject_pattern \
  "account-private audio state is not written to an ownerless App Group key" \
  '[.]set\(' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+P89.swift"

reject_pattern \
  "ownerless continue-reading snapshots are not replayed by app intents or quick actions" \
  'SharedStateReader\(\)[.]load\(\)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/Intents/StartDailyReadingIntent.swift" \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/Intents/StartAudioNarrationIntent.swift" \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel+P86.swift"

require_pattern \
  "runtime widget snapshots fail closed without reading ownerless private values" \
  '[.]ownerlessQuarantined' \
  "$repo_root/ChapterflowWidgets/WidgetDataReader.swift"

reject_pattern \
  "ownerless Control Widgets are not registered before account binding" \
  '(StartReadingControl\(\)|StartReviewControl\(\)|AudioPlaybackControl\(\))' \
  "$repo_root/ChapterflowWidgets/ChapterflowWidgetsBundle.swift"

reject_pattern \
  "cached external audio and control intents emit no ownerless commands" \
  '[.]set\(' \
  "$repo_root/ChapterflowWidgets/ControlWidgetIntents.swift" \
  "$repo_root/ChapterFlow/LiveActivities/AudioPlaybackIntents.swift"

reject_pattern \
  "ownerless reading-minute intent is not donated or persisted" \
  '(LogDailyReadingIntent\(\)|[.]set\()' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/Intents/ChapterFlowShortcutsProvider.swift" \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/Intents/LogDailyReadingIntent.swift"

require_pattern \
  "quarantined widgets show an explicit unavailable state" \
  'WidgetAccountDataUnavailableView\(\)' \
  "$repo_root/ChapterflowWidgets/ContinueReadingWidget.swift" \
  "$repo_root/ChapterflowWidgets/StreakWidget.swift" \
  "$repo_root/ChapterflowWidgets/ProgressRingWidget.swift" \
  "$repo_root/ChapterflowWidgets/NextReviewWidget.swift"

require_pattern \
  "session lifecycle owns reversible audio quiesce" \
  'audioPlayerModel[.]pauseForSessionBoundary\(\)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/SessionScope.swift"

require_pattern \
  "account boundaries invalidate cached WidgetKit timelines" \
  'reloadAllTimelines\(\)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel.swift"

require_pattern \
  "account boundaries invalidate cached Control Widget values" \
  'reloadAllControls\(\)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/AppModel.swift"

require_pattern \
  "irreversible scope teardown cancels account-owned review notifications" \
  'ReviewNotificationScheduler[.]shared[.]cancelAll\(\)' \
  "$repo_root/Packages/AppFeature/Sources/AppFeature/SessionScope.swift"

require_pattern \
  "active A must sign out before a B sign-in can begin" \
  'currentIdentity[[:space:]]*==[[:space:]]*nil' \
  "$repo_root/Packages/AuthKit/Sources/AuthKit/SessionManager.swift"

if (( failures > 0 )); then
  exit 1
fi

echo "PASS: WP-ID-01A identity compile boundaries are enforced"
