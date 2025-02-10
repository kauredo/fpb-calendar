require 'uri'
require 'net/http'
require 'openssl'
require 'json'
require 'nokogiri'
require 'date'
require 'googleauth'
require 'google/apis/calendar_v3'
require 'dotenv'
require 'pry'
require 'base64'

Dotenv.load

CALENDAR_MAPPING_FILE = 'calendars.json'.freeze
EMAILS_FILE = 'emails.txt'.freeze
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

class FpbCalendar
  attr_reader :url, :team_data, :service, :file_path

  def initialize(url)
    @url = url.sub('https://www.fpb.pt/equipa/', '').sub('/', '').prepend('https://www.fpb.pt/equipa/')
    @team_data = extract_team_data
    @file_path = './tmp/temp_google_credentials.json'
    initialize_credentials_file
    @service = initialize_google_calendar_service
  end

  def initialize_credentials_file
    encoded_credentials = ENV['GOOGLE_CALENDAR_CREDENTIALS']
    File.write(file_path, Base64.decode64(encoded_credentials))
  end

  def cleanup
    # Delete the temporary credentials file after use
    File.delete(file_path) if File.exist?(file_path)
  end

  # Extract team data from the FPB website
  def extract_team_data
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    max_redirects = 5
    redirects = 0

    while redirects < max_redirects
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      # If it's a redirect, follow it
      if response.code.to_i == 301 || response.code.to_i == 302
        uri = URI.parse(response['Location'])
        redirects += 1
      else
        break # No redirect, or we've reached the final response
      end
    end

    if redirects >= max_redirects
      raise "Too many redirects for URL: #{url}"
    end

    # Process the final response
    html = response.body
    doc = Nokogiri::HTML(html)

    team_name = doc.css('div.team-nome').text.strip
    games = parse_games(doc)

    { team_name: team_name, games: games }
  end

  # Parse games from the team page
  def parse_games(doc)
    games = []
    day_wrappers = doc.css('div.day-wrapper')

    day_wrappers.each do |day_wrapper|
      date_element = day_wrapper.at_css('h3.date')
      next unless date_element

      date_text = date_element.text.strip
      next if date_text.to_i.zero?

      day, month_abbr, year = date_text.split(/\s+/)
      english_month_abbr = MONTH_MAP[month_abbr.upcase] || month_abbr
      date = Date.strptime("#{english_month_abbr} #{day}, #{year}", "%b %d, %Y")
      next if date < Date.today

      games.concat(parse_game_details(day_wrapper, date))
    end

    games
  end

  # Parse details for individual games
  def parse_game_details(day_wrapper, date)
    games = []
    game_wrappers = day_wrapper.css('div.game-wrapper')

    game_wrappers.each do |game_wrapper|
      time_text = game_wrapper.at_css('div.hour')&.text&.strip || ''
      teams = game_wrapper.css('span.fullName').map(&:text).map(&:strip)
      location_element = game_wrapper.at_css('div.location-wrapper')
      competition = location_element&.css('div.competition')&.text&.strip
      location = location_element&.text&.strip.split("\r\n").map(&:strip).reject(&:empty?) - [competition]
      # the link is on the parent element
      link = game_wrapper.parent['href']

      games << {
        date: date,
        time: time_text,
        teams: teams,
        location: location.first,
        competition: competition,
        link: link
      }
    end

    games
  end

  # Initialize the Google Calendar API service
  def initialize_google_calendar_service
    scopes = ['https://www.googleapis.com/auth/calendar']
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(file_path),
      scope: scopes
    )

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = credentials
    service
  end

  # Find or create a calendar for the team
  def find_or_create_calendar
    calendars = load_calendar_mappings

    if calendars.key?(url)
      calendar_id = calendars[url]
      begin
        service.get_calendar(calendar_id)
        puts "Found existing calendar for URL #{url}"
      rescue Google::Apis::ClientError
        puts "Calendar not found, creating a new one..."
        calendar_id = create_calendar
        update_calendar_mappings(calendars, calendar_id)
      end
    else
      puts "No calendar mapping found, creating a new one..."
      calendar_id = create_calendar
      update_calendar_mappings(calendars, calendar_id)
    end

    calendar_id
  end

  # Create a new Google Calendar
  def create_calendar
    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary: team_data[:team_name],
      time_zone: 'Europe/Lisbon'
    )
    result = service.insert_calendar(calendar)
    puts "Created calendar: #{result.summary} (ID: #{result.id})"
    result.id
  end

  # Load calendar mappings from the JSON file
  def load_calendar_mappings
    File.exist?(CALENDAR_MAPPING_FILE) ? JSON.parse(File.read(CALENDAR_MAPPING_FILE)) : {}
  end

  # Update calendar mappings in the JSON file
  def update_calendar_mappings(calendars, calendar_id)
    calendars[url] = calendar_id
    File.write(CALENDAR_MAPPING_FILE, JSON.pretty_generate(calendars))
  end

  # Share the calendar with email addresses
  def share_calendar_with_emails(calendar_id)
    emails = File.readlines(EMAILS_FILE).map(&:strip)

    emails.each do |email|
      share_calendar_with_email(calendar_id, email, role: 'writer')
    end
  end

  def share_calendar_with_email(calendar_id, email, role: 'reader')
    # List the existing ACL rules for the calendar
    acl_list = service.list_acls(calendar_id).items

    # Check if the calendar is already shared with this email
    already_shared = acl_list.any? do |acl|
      acl.scope.type == 'user' && acl.scope.value == email
    end

    unless already_shared
      acl_rule = Google::Apis::CalendarV3::AclRule.new(
        scope: Google::Apis::CalendarV3::AclRule::Scope.new(type: 'user', value: email),
        role: role
      )
      service.insert_acl(calendar_id, acl_rule)
      puts "Shared calendar #{calendar_id} with #{email}"
    else
      puts "Calendar #{calendar_id} is already shared with #{email}"
    end
  end


  # Add games to the Google Calendar
  def add_games_to_calendar(calendar_id)
    team_data[:games].each do |game|
      start_time = Time.parse("#{game[:date]} #{game[:time]}")
      end_time = start_time + 9000 # Adjust duration as needed
      event_summary = "#{game[:teams].first} vs #{game[:teams].last}"
      event_description = <<~DESC
        Competição: #{game[:competition]}
        Link: https://www.fpb.pt#{game[:link]}
      DESC

      # Query for existing events in a time window around start_time
      existing_events = service.list_events(calendar_id,
        single_events: true,
        order_by: 'startTime',
        time_min: start_time.iso8601,
        time_max: (start_time + 3600).iso8601,  # adjust time window as needed
        q: event_summary
      ).items

      existing_event = existing_events.find { |event| event.summary == event_summary }

      if existing_event
        if existing_event.description == event_description
          puts "Event already exists with the same description: #{event_summary}"
          next
        else
          puts "Updating the event description for: #{event_summary}"
          existing_event.description = event_description
          service.update_event(calendar_id, existing_event.id, existing_event)
          next
        end
      end

      event = Google::Apis::CalendarV3::Event.new(
        summary: event_summary,
        description: event_description,
        location: game[:location],
        start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start_time.iso8601, time_zone: 'Europe/Lisbon'),
        end: Google::Apis::CalendarV3::EventDateTime.new(date_time: end_time.iso8601, time_zone: 'Europe/Lisbon'),
        visibility: 'public'
      )
      service.insert_event(calendar_id, event)
      puts "Added event: #{event.summary}"
    end
  end

  def calendar_link(calendar_id)
    "https://calendar.google.com/calendar/embed?src=#{calendar_id}"
  end
end
