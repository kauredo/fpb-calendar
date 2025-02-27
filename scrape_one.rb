require_relative 'fpb_calendar'

team_id = ARGV[0]&.to_i

unless team_id && team_id > 0
  puts 'Please provide a team ID as an argument'
  puts 'Usage: ruby scrape_one.rb TEAM_ID'
  exit 1
end

calendar = FpbCalendar.new("https://www.fpb.pt/equipa/equipa_#{team_id}")

# Find or create a calendar
calendar_id = calendar.find_or_create_calendar

# Add games to the calendar
calendar.add_games_to_calendar(calendar_id)
calendar.remove_stale_events(calendar_id)

# Delete the temp files
calendar.cleanup
