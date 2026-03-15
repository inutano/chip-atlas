require "yaml"
require "time"

module PJ
  module Maintenance
    CONFIG_PATH = File.join(__dir__, "..", "..", "config", "maintenance.yml")

    def self.current_status(now = Time.now)
      config = YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Time, Date])
      active_key = config["current_maintenance"]

      if active_key.nil?
        return { phase: 0, message: nil, ea_endpoint: nil }
      end

      window = config.dig("maintenance_windows", active_key)
      if window.nil?
        return { phase: 0, message: nil, ea_endpoint: nil }
      end

      phases = window["phases"]
      phases.each do |p|
        start_time = Time.parse(p["start"].to_s)
        end_time = p["end"] ? Time.parse(p["end"].to_s) : nil

        if now >= start_time && (end_time.nil? || now < end_time)
          return {
            phase: p["phase"],
            message: p["announcement"],
            ea_endpoint: p["ea_endpoint"]
          }
        end
      end

      { phase: 0, message: nil, ea_endpoint: nil }
    end
  end
end
