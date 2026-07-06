#!/usr/bin/env ruby
# Adds the ChapterflowWidgets WidgetKit extension target to ChapterFlow.xcodeproj.
# Uses the xcodeproj gem to avoid manual pbxproj edits (which have caused parse
# errors twice on P9.6).
#
# Usage: ruby scripts/add_widget_target.rb

require 'xcodeproj'

PROJECT_PATH     = '/Users/radinsoltani/cf-ios-p8-1/ChapterFlow.xcodeproj'
WIDGET_NAME      = 'ChapterflowWidgets'
BUNDLE_ID        = 'com.chapterflow.ios.widgets'
WIDGET_DIR       = 'ChapterflowWidgets'
APP_GROUP        = 'group.com.chapterflow'
DEPLOYMENT_TARGET = '18.0'
SWIFT_VERSION    = '6.0'

SOURCE_FILES = %w[
  ChapterflowWidgetsBundle.swift
  WidgetDataReader.swift
  StreakWidget.swift
  ContinueReadingWidget.swift
  ProgressRingWidget.swift
  NextReviewWidget.swift
].freeze

puts "Opening #{PROJECT_PATH}…"
proj = Xcodeproj::Project.open(PROJECT_PATH)

# Guard: skip if the target already exists (idempotent).
if proj.targets.any? { |t| t.name == WIDGET_NAME }
  puts "Target '#{WIDGET_NAME}' already exists — nothing to do."
  exit 0
end

# ── 1. Create the app-extension target ────────────────────────────────────────
widget_target = proj.new_target(:app_extension, WIDGET_NAME, :ios, DEPLOYMENT_TARGET)

# ── 2. File-system group + source files ───────────────────────────────────────
widget_group = proj.main_group.new_group(WIDGET_DIR, WIDGET_DIR)

SOURCE_FILES.each do |filename|
  ref = widget_group.new_file(filename)
  widget_target.source_build_phase.add_file_reference(ref)
end

info_ref = widget_group.new_file('Info.plist')
widget_group.new_file("#{WIDGET_NAME}.entitlements")

# ── 3. Build settings ─────────────────────────────────────────────────────────
widget_target.build_configurations.each do |config|
  s = config.build_settings

  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['INFOPLIST_FILE']            = "#{WIDGET_DIR}/Info.plist"
  s['GENERATE_INFOPLIST_FILE']   = 'NO'
  s['CODE_SIGN_ENTITLEMENTS']    = "#{WIDGET_DIR}/#{WIDGET_NAME}.entitlements"

  s['SWIFT_VERSION']             = SWIFT_VERSION
  s['IPHONEOS_DEPLOYMENT_TARGET']= DEPLOYMENT_TARGET
  s['TARGETED_DEVICE_FAMILY']    = '1,2'

  s['MARKETING_VERSION']         = '1.0'
  s['CURRENT_PROJECT_VERSION']   = '1'

  s['SKIP_INSTALL']              = 'YES'
  s['CODE_SIGN_STYLE']           = 'Automatic'

  # WidgetKit extensions need Swift 6 strict concurrency.
  s['SWIFT_STRICT_CONCURRENCY']  = 'complete'
end

# ── 4. Frameworks: WidgetKit + SwiftUI ────────────────────────────────────────
frameworks_group = proj.frameworks_group

def find_or_create_framework(group, name)
  existing = group.children.find { |c| c.respond_to?(:path) && c.path == "#{name}.framework" }
  return existing if existing
  ref = group.new_file("System/Library/Frameworks/#{name}.framework", :sdk_root)
  ref.last_known_file_type = 'wrapper.framework'
  ref.source_tree = 'SDKROOT'
  ref.path = "#{name}.framework"
  ref
end

widgetkit_ref = find_or_create_framework(frameworks_group, 'WidgetKit')
swiftui_ref   = find_or_create_framework(frameworks_group, 'SwiftUI')

widget_target.frameworks_build_phase.add_file_reference(widgetkit_ref)
widget_target.frameworks_build_phase.add_file_reference(swiftui_ref)

# ── 5. Embed the extension in the main app ────────────────────────────────────
main_app = proj.targets.find { |t| t.name == 'ChapterFlow' }
abort 'ERROR: ChapterFlow target not found' unless main_app

embed_phase = main_app.copy_files_build_phases
                       .find { |p| p.name == 'Embed App Extensions' }

unless embed_phase
  embed_phase = main_app.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.dst_subfolder_spec = '13' # PlugIns
end

embed_build_file = proj.new(Xcodeproj::Project::Object::PBXBuildFile)
embed_build_file.file_ref = widget_target.product_reference
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
embed_phase.files << embed_build_file

# ── 6. Target dependency: app → widget ───────────────────────────────────────
main_app.add_dependency(widget_target)

# ── 7. Save ───────────────────────────────────────────────────────────────────
proj.save
puts "Saved. Target '#{WIDGET_NAME}' added successfully."

# ── 8. Sanity-check: re-open and verify ──────────────────────────────────────
check = Xcodeproj::Project.open(PROJECT_PATH)
names = check.targets.map(&:name)
abort "ERROR: #{WIDGET_NAME} not found after save!" unless names.include?(WIDGET_NAME)
puts "Verification OK. Targets: #{names.join(', ')}"
