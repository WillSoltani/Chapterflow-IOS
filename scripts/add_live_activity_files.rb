#!/usr/bin/env ruby
# Adds Live Activity source files (P8.2) to the ChapterflowWidgets extension target.
#
# Files compiled by BOTH app + widget targets:
#   ChapterFlow/LiveActivities/ReadingSessionAttributes.swift
#   ChapterFlow/LiveActivities/StreakAtRiskAttributes.swift
#   ChapterFlow/LiveActivities/AudioPlaybackIntents.swift
#
# The ChapterFlow app target uses PBXFileSystemSynchronizedRootGroup (path=ChapterFlow)
# so all files under ChapterFlow/ compile automatically into the app — no pbxproj edit
# needed for the app side. We only need to add the shared files to the widget target.
#
# Files compiled ONLY by the widget target:
#   ChapterflowWidgets/ReadingSessionLiveActivity.swift
#   ChapterflowWidgets/StreakAtRiskLiveActivity.swift

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../ChapterFlow.xcodeproj', __dir__)
project = Xcodeproj::Project.open(PROJECT_PATH)

widget_target = project.targets.find { |t| t.name == 'ChapterflowWidgets' }
abort("ERROR: ChapterflowWidgets target not found") unless widget_target

widget_group = project.main_group.find_subpath('ChapterflowWidgets', false)
abort("ERROR: ChapterflowWidgets group not found") unless widget_group

# ── 1. Shared attributes / intents (SOURCE_ROOT-relative, live in ChapterFlow/) ──────

# Create or find a group for the shared files under the project root (not inside
# ChapterflowWidgets/) so the path is explicit from SOURCE_ROOT.
live_activity_group = project.main_group.find_subpath('LiveActivityShared', false) ||
                      project.main_group.new_group('LiveActivityShared', 'ChapterFlow/LiveActivities')

shared_files = %w[
  ReadingSessionAttributes.swift
  StreakAtRiskAttributes.swift
  AudioPlaybackIntents.swift
]

shared_files.each do |filename|
  # Skip if already present in the widget target's sources
  already_in_target = widget_target.source_build_phase.files_references.any? do |ref|
    ref.path == filename && ref.parent == live_activity_group
  end
  next if already_in_target

  # Create or reuse the file reference
  file_ref = live_activity_group.files.find { |f| f.path == filename } ||
             live_activity_group.new_file(filename)
  file_ref.source_tree = '<group>'

  widget_target.source_build_phase.add_file_reference(file_ref)
  puts "Added shared file to widget target: #{filename}"
end

# ── 2. Widget-only Live Activity views (already in ChapterflowWidgets/) ───────────────

widget_only_files = %w[
  ReadingSessionLiveActivity.swift
  StreakAtRiskLiveActivity.swift
]

widget_only_files.each do |filename|
  already_in_target = widget_target.source_build_phase.files_references.any? do |ref|
    ref.path == filename
  end
  next if already_in_target

  file_ref = widget_group.files.find { |f| f.path == filename } ||
             widget_group.new_file(filename)
  file_ref.source_tree = '<group>'

  widget_target.source_build_phase.add_file_reference(file_ref)
  puts "Added widget-only file to widget target: #{filename}"
end

project.save
puts "Project saved successfully."

# ── Validate ──────────────────────────────────────────────────────────────────────────
puts "\nValidating..."
reopened = Xcodeproj::Project.open(PROJECT_PATH)
wt = reopened.targets.find { |t| t.name == 'ChapterflowWidgets' }
sources = wt.source_build_phase.files.map { |f| f.file_ref&.path }.compact
puts "ChapterflowWidgets sources: #{sources.inspect}"

expected = shared_files + widget_only_files
missing  = expected.reject { |f| sources.any? { |s| s == f } }
if missing.empty?
  puts "All Live Activity files wired correctly."
else
  abort("ERROR: Missing from widget sources: #{missing.inspect}")
end
