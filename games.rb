# frozen_string_literal: true

require_relative 'fpb_calendar'
require 'json'
require 'pry'

calendar_mappings = File.exist?(CALENDAR_MAPPING_FILE) ? JSON.parse(File.read(CALENDAR_MAPPING_FILE)) : {}
return unless calendar_mappings

calendar_urls = calendar_mappings.keys
calendar_urls.each do |url|
  # Initialize the FpbCalendar instance
  calendar = FpbCalendar.new(url)

  # Find or create a calendar
  calendar_id = calendar.find_or_create_calendar

  # Share the calendar with the provided email
  calendar.share_calendar_with_emails(calendar_id)

  # Add games to the calendar
  calendar.add_games_to_calendar(calendar_id)
  calendar.remove_stale_events(calendar_id)

  # Delete the temp files
  calendar.cleanup
end
