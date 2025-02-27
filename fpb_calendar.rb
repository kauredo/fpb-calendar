# frozen_string_literal: true

# fpb_calendar.rb
require_relative 'services/fpb_scraper'
require 'googleauth'
require 'google/apis/calendar_v3'
require 'dotenv'
require 'json'
require 'base64'
require 'pry'

Dotenv.load

CALENDAR_MAPPING_FILE = 'calendars.json'
EMAILS_FILE = 'emails.txt'

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
    puts '-' * 20
    puts "Processing team: #{team_name}"
    calendars = load_calendar_mappings

    if calendars.key?(url)
      calendar_id = calendars[url]
      begin
        calendar = service.get_calendar(calendar_id)
        puts "Found existing calendar for URL #{url}"

        if calendar.summary != team_name
          puts "Team name changed from '#{calendar.summary}' to '#{team_name}'"
          calendar.summary = team_name
          service.update_calendar(calendar_id, calendar)
          puts "Updated calendar name to: #{team_name}"
        end
      rescue Google::Apis::ClientError
        puts 'Calendar not found, creating a new one...'
        calendar_id = create_calendar
        update_calendar_mappings(calendars, calendar_id)
      end
    else
      puts 'No calendar mapping found, creating a new one...'
      calendar_id = create_calendar
      update_calendar_mappings(calendars, calendar_id)
    end

    calendar_id
  end

  def create_calendar
    calendar = Google::Apis::CalendarV3::Calendar.new(
      summary: team_name,
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

    if already_shared
      puts "Calendar #{team_name} is already shared with #{email}"
    else
      acl_rule = Google::Apis::CalendarV3::AclRule.new(
        scope: Google::Apis::CalendarV3::AclRule::Scope.new(type: 'user', value: email),
        role: role
      )
      service.insert_acl(calendar_id, acl_rule)
      puts "Shared calendar #{team_name} with #{email}"
    end
  end

  def list_acls(calendar_id)
    acl_list = service.list_acls(calendar_id).items
    acl_list_without_owners = acl_list.reject { |acl| acl.role == 'owner' }
    puts "Listing ACLs for calendar: #{team_name}. Total ACLs: #{acl_list_without_owners.size}"
    acl_list_without_owners.each do |acl|
      puts "#{acl.scope.value} - #{acl.role}"
    end
  end

  def add_games_to_calendar(calendar_id)
    team_data[:games].each do |game|
      # Skip past games
      # next if game[:time].empty?

      # Create event time data
      start_time = Time.parse("#{game[:date]} #{game[:time]}")
      end_time = start_time + 9000 # 2.5 hours in seconds

      start_of_day = Time.parse("#{game[:date]} 00:00:00")
      end_of_day = Time.parse("#{game[:date]} 23:59:59")

      # Create event metadata
      event_summary = "#{game[:teams].first} vs #{game[:teams].last}"
      result = if game[:result].nil?
                 nil
               else
                 scores = game[:result].split('-').map(&:to_i)
                 "#{game[:teams].first} #{scores.first} - #{scores.last} #{game[:teams].last}"
               end
      event_description = if result.nil?
                            <<~DESC
                              Competição: #{game[:competition]}
                              Link: #{game[:link]}
                            DESC
                          else
                            <<~DESC
                              Competição: #{game[:competition]}
                              Resultado: #{result}
                              Link: #{game[:link]}
                            DESC
                          end

      # Check for existing events with the same summary on the same day
      existing_events = service.list_events(
        calendar_id,
        single_events: true,
        order_by: 'startTime',
        time_min: start_of_day.iso8601,
        time_max: end_of_day.iso8601,
        q: event_summary
      ).items

      existing_event = existing_events.find { |event| event.summary == event_summary }

      # Handle existing events
      if existing_event
        if existing_event.description == event_description || result.nil?
          puts "Event already exists with the same description: #{event_summary}, #{existing_event.start.date_time}"
        else
          puts "Updating the event description for: #{event_summary}, #{existing_event.start.date_time}"
          existing_event.description = event_description
          service.update_event(calendar_id, existing_event.id, existing_event)
        end

        next
      end

      # Create and add new event
      event = Google::Apis::CalendarV3::Event.new(
        summary: event_summary,
        description: event_description,
        location: game[:location],
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_time.iso8601,
          time_zone: 'Europe/Lisbon'
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: end_time.iso8601,
          time_zone: 'Europe/Lisbon'
        ),
        visibility: 'public'
      )

      puts "Added event: #{event.summary}, #{event.start.date_time}"
      service.insert_event(calendar_id, event)
    end
  end

  def remove_stale_events(calendar_id)
    events = service.list_events(
      calendar_id,
      single_events: true,
      order_by: 'startTime'
    ).items

    current_games = team_data[:games].map do |game|
      {
        summary: "#{game[:teams].first} vs #{game[:teams].last}",
        date_time: Time.parse("#{game[:date]} #{game[:time]}").iso8601,
        result: game[:result]
      }
    end

    # Group future events by summary (team names)
    future_events = events.select { |event| event.start.date_time > DateTime.now }
    events_by_summary = future_events.group_by(&:summary)

    events_to_remove = []

    # For each group of events with the same summary
    events_by_summary.each do |summary, matching_events|
      # Find matching current games
      matching_games = current_games.select { |game| game[:summary] == summary && game[:result].nil? }

      # If we have matches, we need to keep only those with matching date_times
      next unless matching_games.any?

      matching_events.each do |event|
        # Keep if any game has matching date_time
        should_keep = matching_games.any? do |game|
          event.start.date_time.to_s == game[:date_time]
        end

        # Add to remove list if we shouldn't keep it
        events_to_remove << event unless should_keep
      end
    end

    if events_to_remove.empty?
      puts 'No stale events to remove'
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
      puts "#{calendar.summary}: #{calendar.id}"
    end
    puts '-' * 20

    calendars.each do |calendar|
      puts "#{calendar.summary}:"
      tmp.list_acls(calendar.id)
      puts
    end
  end

  def self.delete_calendar(calendar_id)
    tmp = new('https://www.fpb.pt/equipa/')
    service = tmp.service
    service.delete_calendar(calendar_id)
    puts "Deleted calendar: #{calendar_id}"
  end
end
