#!/usr/bin/env ruby
# Adds the TestSupport source files and the StoreKit config to ChapterFlow.xcodeproj.
# These files are added to the ChapterFlow app target and a new TestSupport group.
#
# Usage: ruby scripts/add_testsupport_files.rb

require 'xcodeproj'

WORKTREE_ROOT = File.expand_path('..', __dir__)
PROJECT_PATH  = File.join(WORKTREE_ROOT, 'ChapterFlow.xcodeproj')

# ── Files to add to the ChapterFlow app target ────────────────────────────────
TEST_SUPPORT_FILES = %w[
  CFStubURLProtocol.swift
  CFStubRoutes.swift
  CFUITestSessionSeeder.swift
  CFAppLaunchSupport.swift
].freeze

puts "Opening #{PROJECT_PATH}..."
proj = Xcodeproj::Project.open(PROJECT_PATH)

app_target = proj.targets.find { |t| t.name == 'ChapterFlow' }
abort "ERROR: ChapterFlow target not found." unless app_target

# ── 1. TestSupport group (under ChapterFlow/) ─────────────────────────────────
chapterflow_group = proj.main_group.children.find { |g| g.path == 'ChapterFlow' }
abort "ERROR: ChapterFlow group not found." unless chapterflow_group

# Skip if the TestSupport group already exists.
unless chapterflow_group.children.any? { |g| g.respond_to?(:path) && g.path == 'TestSupport' }
  test_support_group = chapterflow_group.new_group('TestSupport', 'TestSupport')

  TEST_SUPPORT_FILES.each do |filename|
    ref = test_support_group.new_file(filename)
    app_target.source_build_phase.add_file_reference(ref)
  end

  puts "Added TestSupport group with #{TEST_SUPPORT_FILES.length} files."
else
  puts "TestSupport group already exists — skipping."
end

# ── 2. StoreKit configuration resource ────────────────────────────────────────
config_group = chapterflow_group.children.find { |g| g.respond_to?(:path) && g.path == 'Config' }
if config_group && !config_group.children.any? { |f| f.respond_to?(:path) && f.path == 'ChapterFlow.storekit' }
  storekit_ref = config_group.new_file('ChapterFlow.storekit')
  # Add to the app target's resource build phase.
  app_target.resources_build_phase.add_file_reference(storekit_ref)
  puts "Added ChapterFlow.storekit to Config group."
else
  puts "StoreKit config already present — skipping."
end

# ── 3. Save & verify ──────────────────────────────────────────────────────────
proj.save
puts "Saved successfully."

check = Xcodeproj::Project.open(PROJECT_PATH)
cf_group = check.main_group.children.find { |g| g.path == 'ChapterFlow' }
ts_group = cf_group&.children&.find { |g| g.respond_to?(:path) && g.path == 'TestSupport' }
abort "ERROR: TestSupport group not found after save!" unless ts_group

puts "Verification OK. TestSupport group has #{ts_group.children.count} children."
