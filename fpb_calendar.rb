# fpb_calendar.rb
require_relative 'services/fpb_scraper'
require 'googleauth'
require 'google/apis/calendar_v3'
require 'dotenv'
require 'json'
require 'base64'

Dotenv.load

CALENDAR_MAPPING_FILE = 'calendars.json'.freeze
EMAILS_FILE = 'emails.txt'.freeze

class FpbCalendar
  attr_reader :url, :team_data, :service, :file_path

  def initialize(url)
    @url = url.sub('https://www.fpb.pt/equipa/', '').sub('/', '').prepend('https://www.fpb.pt/equipa/')
    scraper = FpbScraper.new(@url)
    @team_data = scraper.fetch_team_data
    @file_path = './tmp/temp_google_credentials.json'
    initialize_credentials_file
    @service = initialize_google_calendar_service
  end

  def initialize_credentials_file
    encoded_credentials = ENV['GOOGLE_CALENDAR_CREDENTIALS']
    File.write(file_path, Base64.decode64(encoded_credentials))
  end

  def cleanup
    File.delete(file_path) if File.exist?(file_path)
  end

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

  def find_or_create_calendar
    puts "-" * 20
    puts "Processing team: #{team_name}"
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

  def create_calendar
    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary: team_data[:team_name],
      time_zone: 'Europe/Lisbon'
    )
    result = service.insert_calendar(calendar)
    puts "Created calendar: #{result.summary} (ID: #{result.id})"
    result.id
  end

  def load_calendar_mappings
    File.exist?(CALENDAR_MAPPING_FILE) ? JSON.parse(File.read(CALENDAR_MAPPING_FILE)) : {}
  end

  def update_calendar_mappings(calendars, calendar_id)
    calendars[url] = calendar_id
    File.write(CALENDAR_MAPPING_FILE, JSON.pretty_generate(calendars))
  end

  def share_calendar_with_emails(calendar_id)
    emails = File.readlines(EMAILS_FILE).map(&:strip)

    emails.each do |email|
      share_calendar_with_email(calendar_id, email, role: 'writer')
    end
  end

  def share_calendar_with_email(calendar_id, email, role: 'reader')
    acl_list = service.list_acls(calendar_id).items

    already_shared = acl_list.any? do |acl|
      acl.scope.type == 'user' && acl.scope.value == email
    end

    unless already_shared
      acl_rule = Google::Apis::CalendarV3::AclRule.new(
        scope: Google::Apis::CalendarV3::AclRule::Scope.new(type: 'user', value: email),
        role: role
      )
      service.insert_acl(calendar_id, acl_rule)
      puts "Shared calendar #{team_name} with #{email}"
    else
      puts "Calendar #{team_name} is already shared with #{email}"
    end
  end

  def list_acls(calendar_id)
    acl_list = service.list_acls(calendar_id).items
    acl_list_without_owners = acl_list.select { |acl| acl.role != 'owner' }
    puts "Listing ACLs for calendar: #{team_name}. Total ACLs: #{acl_list_without_owners.size}"
    acl_list_without_owners.each do |acl|
      puts "#{acl.scope.value} - #{acl.role}"
    end
  end

  def add_games_to_calendar(calendar_id)
    team_data[:games].each do |game|
      start_time = Time.parse("#{game[:date]} #{game[:time]}")
      end_time = start_time + 9000 # 2.5 hours in seconds
      event_summary = "#{game[:teams].first} vs #{game[:teams].last}"
      event_description = <<~DESC
        Competição: #{game[:competition]}
        Link: https://www.fpb.pt#{game[:link]}
      DESC

      existing_events = service.list_events(calendar_id,
        single_events: true,
        order_by: 'startTime',
        time_min: start_time.iso8601,
        time_max: (start_time + 3600).iso8601,
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

  def remove_stale_events(calendar_id)
    time_min = Time.now.utc.iso8601
    events = service.list_events(
      calendar_id,
      single_events: true,
      order_by: 'startTime',
      time_min: time_min
    ).items

    current_games = team_data[:games].map do |game|
      {
        summary: "#{game[:teams].first} vs #{game[:teams].last}",
        date_time: Time.parse("#{game[:date]} #{game[:time]}").iso8601
      }
    end

    events_to_remove = events.reject do |event|
      current_games.any? do |game|
        event.summary == game[:summary] && event.start.date_time.to_s == game[:date_time]
      end
    end

    if events_to_remove.empty?
      puts "No stale events to remove"
    else
      puts "Found #{events_to_remove.size} stale events to remove"
      events_to_remove.each do |event|
        service.delete_event(calendar_id, event.id)
        puts "Removed stale event: #{event.summary}"
      end
    end
  end

  def calendar_link(calendar_id)
    "https://calendar.google.com/calendar/embed?src=#{calendar_id}"
  end

  def team_name
    team_data[:team_name]
  end

  def self.list_all_calendars
    tmp = new('https://www.fpb.pt/equipa/')
    service = tmp.service
    calendars = service.list_calendar_lists.items
    puts "There are #{calendars.size} calendars:"
    calendars.each do |calendar|
      puts "#{calendar.summary}"
    end
    puts "-" * 20

    calendars.each do |calendar|
      puts "#{calendar.summary}:"
      tmp.list_acls(calendar.id)
      puts
    end
  end
end
