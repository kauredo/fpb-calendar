require 'uri'
require 'net/http'
require 'openssl'
require 'json'
require 'nokogiri'
require 'date'
require 'googleauth'
require 'google/apis/calendar_v3'
require 'pry'

# Map Portuguese month abbreviations to English month names
MONTH_MAP = {
  'JAN' => 'Jan',
  'FEV' => 'Feb',
  'MAR' => 'Mar',
  'ABR' => 'Apr',
  'MAI' => 'May',
  'JUN' => 'Jun',
  'JUL' => 'Jul',
  'AGO' => 'Aug',
  'SET' => 'Sep',
  'OUT' => 'Oct',
  'NOV' => 'Nov',
  'DEZ' => 'Dec'
}

KEY_FILE_PATH = './simecq-calendar-0801232616b8.json'

def extract_team_data(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  response = http.get(uri.request_uri)
  html = response.body
  doc = Nokogiri::HTML(html)

  team_name = doc.css('div.team-nome').text.strip

  games = []
  day_wrappers = doc.css('div.day-wrapper')
  day_wrappers.each do |day_wrapper|
    date_element = day_wrapper.at_css('h3.date')
    next unless date_element

    date_text = date_element.text.strip
    next if date_text.to_i.zero?

    day, month_abbr, year = date_text.split(/\s+/)
    # Map Portuguese month abbreviation to English
    english_month_abbr = MONTH_MAP[month_abbr.upcase] || month_abbr

    # Parse the date
    date = Date.strptime("#{english_month_abbr} #{day}, #{year}", "%b %d, %Y")
    next if date < Date.today

    game_wrappers = day_wrapper.css('div.game-wrapper')
    game_wrappers.each do |game_wrapper|
      time_element = game_wrapper.at_css('div.hour')
      time_text = time_element&.text&.strip || ''
      teams = game_wrapper.css('span.fullName').map(&:text).map(&:strip)
      location_element = game_wrapper.at_css('div.location-wrapper')
      competition = location_element&.css('div.competition')&.text&.strip
      location = location_element&.text&.strip.split("\r\n").map { |l| l&.strip }.reject(&:empty?) - [competition]

      games << {
        date: date,
        time: time_text,
        teams: teams,
        location: location.first,
        competition: competition
      }
    end
  end

  { team_name: team_name, games: games }
end

def add_to_google_calendar(service, calendar_id, games)
  games.each do |game|
    # Convert the date and time string to a Time object
    start_time = Time.parse("#{game[:date]} #{game[:time]}")
    event_summary = "#{game[:teams].first} vs #{game[:teams].last}"

    # Query for existing events in a time window around start_time
    existing_events = service.list_events(calendar_id,
      single_events: true,
      order_by: 'startTime',
      time_min: start_time.iso8601,
      time_max: (start_time + 3600).iso8601,  # adjust time window as needed
      q: event_summary
    ).items

    # Skip adding if an event with the same summary already exists
    if existing_events.any? { |event| event.summary == event_summary }
      puts "Event already exists: #{event_summary}"
      next
    end

    event = Google::Apis::CalendarV3::Event.new(
      summary: event_summary,
      description: "#{game[:teams].join(', ')} => #{game[:competition]}",
      location: game[:location],
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time.iso8601,
        time_zone: 'Europe/Lisbon'
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: (start_time + 9000).iso8601, # Adjust duration as needed
        time_zone: 'Europe/Lisbon'
      ),
      visibility: 'public'
    )

    result = service.insert_event(calendar_id, event)
    puts "Added event to calendar '#{calendar_id}': #{result.html_link}"
  end
end

def authorize_google_calendar
  scopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/admin.directory.user'
  ]
  credentials = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(KEY_FILE_PATH),
    scope: scopes
  )
  credentials
end

# Returns the calendar ID for the given URL,
# creating a new calendar if necessary.
def find_or_create_calendar(service, url, team_name, mapping_file = 'calendars.json')
  calendars = File.exist?(mapping_file) ? JSON.parse(File.read(mapping_file)) : {}

  if calendars.key?(url)
    calendar_id = calendars[url]
    begin
      service.get_calendar(calendar_id)
      puts "Found existing calendar for URL #{url}"
    rescue Google::Apis::ClientError => e
      puts "Calendar with ID #{calendar_id} not found; creating a new one..."
      calendar_id = create_calendar_for_team(service, team_name, url)
      calendars[url] = calendar_id
      File.write(mapping_file, calendars.to_json)
    end
  else
    puts "No calendar mapping found for URL #{url}; creating a new calendar..."
    calendar_id = create_calendar_for_team(service, team_name, url)
    calendars[url] = calendar_id
    File.write(mapping_file, calendars.to_json)
  end

  calendar_id
end

def create_calendar_for_team(service, team_name, url)
  # If team_name is nil or empty, fall back to deriving from URL.
  team_name ||= url.split("/").reject(&:empty?).last || "Team Calendar"
  calendar = Google::Apis::CalendarV3::Calendar.new(
    summary: team_name,
    time_zone: 'Europe/Lisbon'
  )
  result = service.insert_calendar(calendar)
  puts "Created new calendar: #{result.summary} (ID: #{result.id})"
  result.id
end

def ensure_calendar_has_team_name(service, calendar_id, team_name)
  current_calendar = service.get_calendar(calendar_id)
  if current_calendar.summary != team_name
    update_calendar_name(service, calendar_id, team_name)
  else
    puts "Calendar #{calendar_id} already has the correct team name."
  end
end

def update_calendar_name(service, calendar_id, new_summary)
  calendar = Google::Apis::CalendarV3::Calendar.new(summary: new_summary)
  service.patch_calendar(calendar_id, calendar)
  puts "Updated calendar #{calendar_id} to new name: #{new_summary}"
end

def share_calendar_with_emails(service, calendar_id, emails_file = 'emails.txt')
  # Read emails from the file, one per line, and remove extra whitespace.
  emails = File.readlines(emails_file).map(&:strip)

  emails.each do |email|
    share_calendar_with_email(service, calendar_id, email)
  end
end

def share_calendar_with_email(service, calendar_id, email)
  # List the existing ACL rules for the calendar
  acl_list = service.list_acls(calendar_id).items

  # Check if the calendar is already shared with this email
  already_shared = acl_list.any? do |acl|
    acl.scope.type == 'user' && acl.scope.value == email
  end

  unless already_shared
    acl_rule = Google::Apis::CalendarV3::AclRule.new(
      scope: Google::Apis::CalendarV3::AclRule::Scope.new(
        type: 'user',
        value: email
      ),
      role: 'writer'
    )
    service.insert_acl(calendar_id, acl_rule)
    puts "Shared calendar #{calendar_id} with #{email}"
  else
    puts "Calendar #{calendar_id} is already shared with #{email}"
  end
end

service = Google::Apis::CalendarV3::CalendarService.new
service.authorization = authorize_google_calendar

# read urls from calendars.json
urls = JSON.parse(File.read('calendars.json')).keys
urls.each do |url|
  team_data = extract_team_data(url)
  team_name = team_data[:team_name]
  games = team_data[:games]

  calendar_id = find_or_create_calendar(service, url, team_name)
  ensure_calendar_has_team_name(service, calendar_id, team_name)

  share_calendar_with_emails(service, calendar_id)
  add_to_google_calendar(service, calendar_id, games)
end

# games.each do |game|
#   puts "Date: #{game[:date]}"
#   puts "Time: #{game[:time]}"
#   puts "Teams: #{game[:teams].join(' vs ')}"
#   puts "Location: #{game[:location]}"
#   puts "Competition: #{game[:competition]}"
#   puts "---"
# end
