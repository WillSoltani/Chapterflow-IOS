#!/usr/bin/env ruby
# Adds the ShareExtension and ActionExtension app-extension targets to
# ChapterFlow.xcodeproj using the xcodeproj gem.
#
# Guardrails:
# - Uses ONLY the xcodeproj gem — never edits project.pbxproj by hand.
# - Sets PRODUCT_NAME = "$(TARGET_NAME)" on each target to prevent
#   "Multiple commands produce" CI failures (cf. P8.1 lesson).
# - Adds both targets to App Group group.com.chapterflow.
# - Extensions do NOT link or import local SPM packages; they use the
#   SharedExtensionKit sources and App Group UserDefaults only (RF4).
#
# Usage:
#   gem install xcodeproj   # once
#   ruby scripts/add_share_action_extensions.rb

require 'xcodeproj'

# ── Configuration ──────────────────────────────────────────────────────────────
PROJECT_PATH     = File.expand_path('../ChapterFlow.xcodeproj', __dir__)
APP_GROUP        = 'group.com.chapterflow'
DEPLOYMENT_TARGET = '18.0'
SWIFT_VERSION    = '6.0'

SHARE_NAME       = 'ShareExtension'
SHARE_BUNDLE_ID  = 'com.chapterflow.ios.shareextension'
SHARE_DIR        = 'ShareExtension'
SHARE_ENTITLEMENTS = "#{SHARE_DIR}/ShareExtension.entitlements"

ACTION_NAME      = 'ActionExtension'
ACTION_BUNDLE_ID = 'com.chapterflow.ios.actionextension'
ACTION_DIR       = 'ActionExtension'
ACTION_ENTITLEMENTS = "#{ACTION_DIR}/ActionExtension.entitlements"

SHARED_KIT_DIR   = 'SharedExtensionKit'

# Source files per target (relative to SOURCE_ROOT).
SHARED_SOURCES = %w[
  ExtensionTokenCheck.swift
  ExtensionOutboxWriter.swift
].freeze

SHARE_SOURCES = %w[
  ShareViewController.swift
  ShareView.swift
].freeze

ACTION_SOURCES = %w[
  ActionViewController.swift
  ActionView.swift
].freeze

puts "Opening #{PROJECT_PATH}…"
proj = Xcodeproj::Project.open(PROJECT_PATH)

main_app = proj.targets.find { |t| t.name == 'ChapterFlow' }
abort('ERROR: ChapterFlow target not found') unless main_app

# ── Helper: find/create a group ────────────────────────────────────────────────
def find_or_create_group(project, path, filesystem_path = nil)
  project.main_group.find_subpath(path, false) ||
    project.main_group.new_group(path, filesystem_path || path)
end

# ── Helper: find/create a framework reference in the frameworks group ──────────
def framework_ref(project, name)
  ref = project.frameworks_group.children.find do |c|
    c.respond_to?(:path) && c.path == "#{name}.framework"
  end
  return ref if ref

  ref = project.frameworks_group.new_file(
    "System/Library/Frameworks/#{name}.framework", :sdk_root
  )
  ref.last_known_file_type = 'wrapper.framework'
  ref.source_tree = 'SDKROOT'
  ref.path = "#{name}.framework"
  ref
end

# ── Helper: build settings applied to every extension target ──────────────────
def apply_base_settings(target, bundle_id, info_plist_path, entitlements_path, dir_name)
  target.build_configurations.each do |config|
    s = config.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER']    = bundle_id
    s['PRODUCT_NAME']                 = '$(TARGET_NAME)' # Prevents "Multiple commands produce"
    s['INFOPLIST_FILE']               = info_plist_path
    s['GENERATE_INFOPLIST_FILE']      = 'NO'
    s['CODE_SIGN_ENTITLEMENTS']       = entitlements_path

    s['SWIFT_VERSION']                = '6.0'
    s['IPHONEOS_DEPLOYMENT_TARGET']   = '18.0'
    s['TARGETED_DEVICE_FAMILY']       = '1,2'

    s['MARKETING_VERSION']            = '1.0'
    s['CURRENT_PROJECT_VERSION']      = '1'

    s['SKIP_INSTALL']                 = 'YES'
    s['CODE_SIGN_STYLE']              = 'Automatic'

    # Swift 6 strict concurrency — required by CLAUDE.md conventions.
    s['SWIFT_STRICT_CONCURRENCY']     = 'complete'
  end
end

# ── Helper: embed an extension in the main app ────────────────────────────────
def embed_extension(project, main_app, ext_target)
  embed_phase = main_app.copy_files_build_phases
                        .find { |p| p.name == 'Embed App Extensions' }

  unless embed_phase
    embed_phase = main_app.new_copy_files_build_phase('Embed App Extensions')
    embed_phase.dst_subfolder_spec = '13' # PlugIns
  end

  already_embedded = embed_phase.files.any? do |f|
    f.file_ref == ext_target.product_reference
  end
  return if already_embedded

  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.file_ref = ext_target.product_reference
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  embed_phase.files << bf
end

# ── 1. Shared kit group + file references ─────────────────────────────────────
shared_group = find_or_create_group(proj, SHARED_KIT_DIR, SHARED_KIT_DIR)

shared_refs = SHARED_SOURCES.map do |filename|
  shared_group.files.find { |f| f.path == filename } ||
    shared_group.new_file(filename)
end

# ── 2. ShareExtension target ──────────────────────────────────────────────────
if proj.targets.any? { |t| t.name == SHARE_NAME }
  puts "Target '#{SHARE_NAME}' already exists — skipping creation."
else
  puts "Creating target '#{SHARE_NAME}'…"
  share_target = proj.new_target(:app_extension, SHARE_NAME, :ios, DEPLOYMENT_TARGET)

  share_group = find_or_create_group(proj, SHARE_DIR, SHARE_DIR)

  # Source files for this target only
  SHARE_SOURCES.each do |filename|
    ref = share_group.files.find { |f| f.path == filename } || share_group.new_file(filename)
    share_target.source_build_phase.add_file_reference(ref)
  end

  # Shared kit sources (compiled into both extension targets)
  shared_refs.each do |ref|
    share_target.source_build_phase.add_file_reference(ref)
  end

  # Info.plist + entitlements (not compiled, just referenced)
  share_group.new_file('Info.plist') unless share_group.files.any? { |f| f.path == 'Info.plist' }
  share_group.new_file('ShareExtension.entitlements') unless share_group.files.any? { |f| f.path == 'ShareExtension.entitlements' }

  # Frameworks: UIKit + SwiftUI (UniformTypeIdentifiers is linked by the SDK automatically)
  [framework_ref(proj, 'UIKit'), framework_ref(proj, 'SwiftUI')].each do |ref|
    share_target.frameworks_build_phase.add_file_reference(ref)
  end

  apply_base_settings(
    share_target,
    SHARE_BUNDLE_ID,
    "#{SHARE_DIR}/Info.plist",
    SHARE_ENTITLEMENTS,
    SHARE_DIR
  )

  embed_extension(proj, main_app, share_target)
  main_app.add_dependency(share_target)

  puts "  '#{SHARE_NAME}' created."
end

# ── 3. ActionExtension target ─────────────────────────────────────────────────
if proj.targets.any? { |t| t.name == ACTION_NAME }
  puts "Target '#{ACTION_NAME}' already exists — skipping creation."
else
  puts "Creating target '#{ACTION_NAME}'…"
  action_target = proj.new_target(:app_extension, ACTION_NAME, :ios, DEPLOYMENT_TARGET)

  action_group = find_or_create_group(proj, ACTION_DIR, ACTION_DIR)

  ACTION_SOURCES.each do |filename|
    ref = action_group.files.find { |f| f.path == filename } || action_group.new_file(filename)
    action_target.source_build_phase.add_file_reference(ref)
  end

  # Shared kit sources (compiled into both extension targets)
  shared_refs.each do |ref|
    action_target.source_build_phase.add_file_reference(ref)
  end

  action_group.new_file('Info.plist') unless action_group.files.any? { |f| f.path == 'Info.plist' }
  action_group.new_file('ActionExtension.entitlements') unless action_group.files.any? { |f| f.path == 'ActionExtension.entitlements' }

  [framework_ref(proj, 'UIKit'), framework_ref(proj, 'SwiftUI')].each do |ref|
    action_target.frameworks_build_phase.add_file_reference(ref)
  end

  apply_base_settings(
    action_target,
    ACTION_BUNDLE_ID,
    "#{ACTION_DIR}/Info.plist",
    ACTION_ENTITLEMENTS,
    ACTION_DIR
  )

  embed_extension(proj, main_app, action_target)
  main_app.add_dependency(action_target)

  puts "  '#{ACTION_NAME}' created."
end

# ── 4. Save ───────────────────────────────────────────────────────────────────
proj.save
puts "\nProject saved successfully."

# ── 5. Validate ───────────────────────────────────────────────────────────────
puts "\nValidating…"
check = Xcodeproj::Project.open(PROJECT_PATH)
names = check.targets.map(&:name)

[SHARE_NAME, ACTION_NAME].each do |name|
  if names.include?(name)
    puts "  ✓ #{name} found in targets"
  else
    abort("  ✗ ERROR: #{name} not found after save!")
  end
end
puts "\nDone. Targets: #{names.join(', ')}"
