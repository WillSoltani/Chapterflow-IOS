#!/usr/bin/env ruby
# Adds the ChapterFlowUITests XCUITest target to ChapterFlow.xcodeproj.
# Uses the xcodeproj gem to avoid manual pbxproj edits (which are brittle).
#
# Usage (from repo root):
#   ruby scripts/add_uitest_target.rb
#
# Idempotent: running a second time is a no-op.

require 'xcodeproj'

WORKTREE_ROOT     = File.expand_path('..', __dir__)
PROJECT_PATH      = File.join(WORKTREE_ROOT, 'ChapterFlow.xcodeproj')
TARGET_NAME       = 'ChapterFlowUITests'
BUNDLE_ID         = 'com.chapterflow.ios.uitests'
UITEST_DIR        = 'ChapterFlowUITests'
DEPLOYMENT_TARGET = '18.0'
SWIFT_VERSION     = '6.0'

# Source files to add (relative to UITEST_DIR)
SOURCE_FILES = %w[
  ChapterFlowUITests.swift
  Flows/SignInFlowTests.swift
  Flows/ReadQuizUnlockFlowTests.swift
  Flows/PurchaseFlowTests.swift
  Flows/SmokeLaneTests.swift
  Support/AppRobot.swift
].freeze

puts "Opening #{PROJECT_PATH}..."
proj = Xcodeproj::Project.open(PROJECT_PATH)

# ── Guard: idempotent ──────────────────────────────────────────────────────────
if proj.targets.any? { |t| t.name == TARGET_NAME }
  puts "Target '#{TARGET_NAME}' already exists — nothing to do."
  exit 0
end

# Locate the host app target.
app_target = proj.targets.find { |t| t.name == 'ChapterFlow' }
abort "ERROR: 'ChapterFlow' app target not found." unless app_target

# ── 1. Create the UI test bundle target ────────────────────────────────────────
uitest_target = proj.new_target(:ui_test_bundle, TARGET_NAME, :ios, DEPLOYMENT_TARGET)

# ── 2. Build settings (every configuration) ────────────────────────────────────
uitest_target.build_configurations.each do |config|
  s = config.build_settings

  # PRODUCT_NAME = "$(TARGET_NAME)" is REQUIRED for a valid UITest bundle.
  # Omitting it produces an empty product name and breaks the build.
  s['PRODUCT_NAME']                        = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER']           = BUNDLE_ID

  s['SWIFT_VERSION']                       = SWIFT_VERSION
  s['IPHONEOS_DEPLOYMENT_TARGET']          = DEPLOYMENT_TARGET
  s['TARGETED_DEVICE_FAMILY']              = '1,2'

  # Wire up the test host (the ChapterFlow app under test).
  s['TEST_HOST']                           = '$(BUILT_PRODUCTS_DIR)/ChapterFlow.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ChapterFlow'
  s['BUNDLE_LOADER']                       = '$(TEST_HOST)'

  s['SWIFT_STRICT_CONCURRENCY']            = 'complete'
  s['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  s['CODE_SIGN_STYLE']                     = 'Automatic'
  s['MARKETING_VERSION']                   = '1.0'
  s['CURRENT_PROJECT_VERSION']             = '1'
  s['GENERATE_INFOPLIST_FILE']             = 'YES'
end

# ── 3. File-system group + source files ────────────────────────────────────────
# Create sub-groups to mirror the directory layout.
uitest_group = proj.main_group.new_group(UITEST_DIR, UITEST_DIR)
flows_group   = uitest_group.new_group('Flows',   'Flows')
support_group = uitest_group.new_group('Support', 'Support')

SOURCE_FILES.each do |rel_path|
  dir_part  = File.dirname(rel_path)
  file_name = File.basename(rel_path)

  group = case dir_part
          when 'Flows'   then flows_group
          when 'Support' then support_group
          else                uitest_group
          end

  ref = group.new_file(file_name)
  uitest_target.source_build_phase.add_file_reference(ref)
end

# ── 4. Target dependency: UITests → ChapterFlow ───────────────────────────────
uitest_target.add_dependency(app_target)

# ── 5. Save ────────────────────────────────────────────────────────────────────
proj.save
puts "Saved. Target '#{TARGET_NAME}' added successfully."

# ── 6. Sanity-check ────────────────────────────────────────────────────────────
check = Xcodeproj::Project.open(PROJECT_PATH)
names = check.targets.map(&:name)
abort "ERROR: #{TARGET_NAME} not found after save!" unless names.include?(TARGET_NAME)

product_names = check.targets
                     .find { |t| t.name == TARGET_NAME }
                     .build_configurations
                     .map { |c| c.build_settings['PRODUCT_NAME'] }
                     .uniq
unless product_names == ['$(TARGET_NAME)']
  abort "ERROR: PRODUCT_NAME not set correctly. Got: #{product_names.inspect}"
end

puts "Verification OK."
puts "Targets: #{names.join(', ')}"
puts "PRODUCT_NAME check: #{product_names.first}"
