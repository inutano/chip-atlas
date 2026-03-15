#!/usr/bin/env ruby
# frozen_string_literal: true

# Update maintenance announcements in views/updates.markdown
# based on config/maintenance.yml phase definitions.
#
# Usage:
#   ruby script/maintenance/update_maintenance.rb            # update announcement
#   ruby script/maintenance/update_maintenance.rb --phase     # print current phase number
#   ruby script/maintenance/update_maintenance.rb --check-only # print what would change, don't write

require "yaml"
require "time"

APP_ROOT = File.expand_path("../..", __dir__)
CONFIG_PATH = File.join(APP_ROOT, "config", "maintenance.yml")
UPDATES_PATH = File.join(APP_ROOT, "views", "updates.markdown")

MARKER_START = "<!-- maintenance-auto-start -->"
MARKER_END = "<!-- maintenance-auto-end -->"

def load_config
  YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Time, Date])
end

def current_phase(config, now = Time.now)
  active_key = config["current_maintenance"]
  return { phase: 0, announcement: nil, ea_endpoint: nil } if active_key.nil?

  window = config.dig("maintenance_windows", active_key)
  return { phase: 0, announcement: nil, ea_endpoint: nil } if window.nil?

  phases = window["phases"]
  current = nil

  phases.each do |p|
    start_time = Time.parse(p["start"].to_s)
    end_time = p["end"] ? Time.parse(p["end"].to_s) : nil

    if now >= start_time && (end_time.nil? || now < end_time)
      current = p
      break
    end
  end

  if current
    {
      phase: current["phase"],
      announcement: current["announcement"],
      ea_endpoint: current["ea_endpoint"]
    }
  else
    # Check if we're past all phases (maintenance complete)
    last_phase = phases.last
    last_start = Time.parse(last_phase["start"].to_s)
    if now >= last_start && last_phase["end"].nil? && last_phase["announcement"].nil?
      # Final phase with no announcement = recovery complete
      { phase: 0, announcement: nil, ea_endpoint: nil }
    else
      { phase: 0, announcement: nil, ea_endpoint: nil }
    end
  end
end

def update_announcement(content, announcement)
  lines = content.lines
  start_idx = lines.index { |l| l.strip == MARKER_START }
  end_idx = lines.index { |l| l.strip == MARKER_END }

  unless start_idx && end_idx && end_idx > start_idx
    warn "ERROR: Marker comments not found in #{UPDATES_PATH}"
    exit 1
  end

  new_lines = lines[0..start_idx]
  if announcement
    new_lines << "- <span style=\"color:red\">**#{announcement}**</span>\n"
  end
  new_lines << lines[end_idx..]

  new_lines.join
end

# --- Main ---

config = load_config
status = current_phase(config)

case ARGV[0]
when "--phase"
  puts status[:phase]
when "--check-only"
  puts "Current phase: #{status[:phase]}"
  if status[:announcement]
    puts "Announcement: #{status[:announcement]}"
  else
    puts "No active announcement"
  end
  if status[:ea_endpoint]
    puts "EA endpoint: #{status[:ea_endpoint]}"
  end
else
  content = File.read(UPDATES_PATH)
  updated = update_announcement(content, status[:announcement])

  if content == updated
    puts "No changes needed"
  else
    File.write(UPDATES_PATH, updated)
    puts "Updated #{UPDATES_PATH}"
    puts "Phase: #{status[:phase]}"
    puts "Announcement: #{status[:announcement] || '(cleared)'}"
  end
end
