#!/usr/bin/env ruby
# frozen_string_literal: true
#
# scripts/l10n-add-catalogs.rb — P10.11 Localization
#
# Idempotently registers a per-target `Localizable.xcstrings` String Catalog for
# the app-extension targets that render user-facing literal text. Run once after
# checking out; safe to re-run (it no-ops when everything is already wired).
#
# Why only the extensions?
#   • The APP target (`ChapterFlow`) uses an Xcode 16 synchronized root group
#     (PBXFileSystemSynchronizedRootGroup, path "ChapterFlow"), so dropping
#     `ChapterFlow/Localizable.xcstrings` into that folder auto-includes it in
#     the target — no project edit required.
#   • The extension targets use classic PBXGroups with explicit file references,
#     so their catalogs must be registered here.
#   • `NotificationService` renders NO user-facing literals, so it gets no
#     catalog (see docs/LOCALIZATION.md).
#
# Each extension has its OWN main bundle, so a single app catalog cannot localize
# strings rendered inside an extension — each needs its own catalog.
#
# Requires the `xcodeproj` gem (`gem install xcodeproj`).

require "xcodeproj"

PROJECT_PATH = File.expand_path("../ChapterFlow.xcodeproj", __dir__)

# target name => folder/group path (relative to project root)
EXTENSION_TARGETS = {
  "ChapterflowWidgets"  => "ChapterflowWidgets",
  "NotificationContent" => "NotificationContent",
  "ShareExtension"      => "ShareExtension",
  "ActionExtension"     => "ActionExtension",
}.freeze

CATALOG_NAME = "Localizable.xcstrings"

project = Xcodeproj::Project.open(PROJECT_PATH)
changed = false

EXTENSION_TARGETS.each do |target_name, group_path|
  target = project.native_targets.find { |t| t.name == target_name }
  raise "Target #{target_name.inspect} not found" if target.nil?

  group = project.main_group.children.find do |child|
    child.isa == "PBXGroup" && child.path == group_path
  end
  raise "Group #{group_path.inspect} not found" if group.nil?

  disk_path = File.join(File.dirname(PROJECT_PATH), group_path, CATALOG_NAME)
  raise "Missing catalog file on disk: #{disk_path}" unless File.exist?(disk_path)

  file_ref = group.files.find { |f| f.display_name == CATALOG_NAME }
  if file_ref.nil?
    file_ref = group.new_reference(CATALOG_NAME)
    file_ref.last_known_file_type = "text.json.xcstrings"
    changed = true
  end

  resources = target.resources_build_phase
  unless resources.files_references.include?(file_ref)
    resources.add_file_reference(file_ref)
    changed = true
  end
end

if changed
  project.save
  puts "✅ Registered extension String Catalogs."
else
  puts "✓ Extension String Catalogs already registered — no changes."
end
