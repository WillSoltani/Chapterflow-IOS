#!/usr/bin/env ruby
# frozen_string_literal: true
#
# P10.13 — wire each target's PrivacyInfo.xcprivacy into its Resources build
# phase. Uses the xcodeproj gem so project.pbxproj is never hand-edited.
# Idempotent: re-running does not create duplicate references or build files.

require 'xcodeproj'
require 'pathname'

PROJECT = File.expand_path('../ChapterFlow.xcodeproj', __dir__)

# target name => a sibling file already referenced by that target's group. The
# new PrivacyInfo.xcprivacy ref is created in the same group with the sibling's
# directory, so its on-disk path resolves next to the sibling.
# NOTE: the main `ChapterFlow` target uses an Xcode file-system-synchronized
# root group (folder `ChapterFlow`), so ChapterFlow/PrivacyInfo.xcprivacy is
# auto-included as a bundle resource with no project edit. Only the classic
# (non-synchronized) extension targets are wired here.
MAP = {
  'ChapterflowWidgets'  => 'ChapterflowWidgets/Info.plist',
  'ShareExtension'      => 'ShareExtension/Info.plist',
  'ActionExtension'     => 'ActionExtension/Info.plist',
  'NotificationService' => 'NotificationService/NotificationServiceExtension.swift',
  'NotificationContent' => 'NotificationContent/NotificationViewController.swift'
}.freeze

BASENAME = 'PrivacyInfo.xcprivacy'

project = Xcodeproj::Project.open(PROJECT)

def sibling_ref(project, sibling_relpath)
  # Match on the resolved on-disk path so that colliding basenames (every
  # extension has its own Info.plist) do not alias to the first match.
  suffix = "/#{sibling_relpath}"
  project.files.find do |ref|
    rp = ref.real_path.to_s
    rp.end_with?(suffix) || File.basename(rp) == sibling_relpath
  end
end

changed = false

MAP.each do |target_name, sibling|
  target = project.targets.find { |t| t.name == target_name }
  raise "target not found: #{target_name}" unless target

  # Skip if this target already copies a PrivacyInfo.xcprivacy resource.
  if target.resources_build_phase.files.any? { |bf| bf.file_ref && File.basename(bf.file_ref.path.to_s) == BASENAME }
    puts "= #{target_name}: already wired, skipping"
    next
  end

  sib = sibling_ref(project, sibling)
  raise "sibling not found for #{target_name}: #{sibling}" unless sib

  group = sib.parent
  # New ref path mirrors the sibling ref's directory (relative to same group).
  sib_dir = File.dirname(sib.path.to_s)
  new_path = sib_dir == '.' ? BASENAME : File.join(sib_dir, BASENAME)

  ref = group.files.find { |f| File.basename(f.path.to_s) == BASENAME }
  ref ||= group.new_reference(new_path)

  # Verify the reference resolves to the file we actually wrote on disk.
  unless File.exist?(ref.real_path.to_s)
    raise "ref resolves to missing file for #{target_name}: #{ref.real_path}"
  end

  target.resources_build_phase.add_file_reference(ref, true)
  changed = true
  puts "+ #{target_name}: added #{new_path} -> #{ref.real_path} (group '#{group.display_name}')"
end

if changed
  project.save
  puts 'Saved project.'
else
  puts 'No changes.'
end
