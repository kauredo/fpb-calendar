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

def extract_games(url)
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE # Be cautious with this in production

  response = http.get(uri.request_uri)
  html = response.body

  doc = Nokogiri::HTML(html)

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
      location = location_element&.text&.strip.split("\r\n").map {|l| l&.strip }.reject(&:empty?) - [competition]

      games << {
        date: date,
        time: time_text,
        teams: teams,
        location: location.first,
        competition: competition
      }
    end
  end

  games
end

def add_to_google_calendar(service, calendar_id, games)
  games.each do |game|
    # Convert the date string to a Time object
    start_time = Time.parse("#{game[:date]} #{game[:time]}")

    event = Google::Apis::CalendarV3::Event.new(
      summary: "#{game[:teams].first} vs #{game[:teams].last}",
      description: "#{game[:teams].join(', ')} => #{game[:competition]}",
      location: game[:location],
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time.iso8601,
        time_zone: 'Europe/Lisbon'
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: (start_time + 9000).iso8601, # Add 3600 seconds for 2.5 hour
        time_zone: 'Europe/Lisbon'
      ),
      visibility: 'public',
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

def get_calendar(service)
  result = service.get_calendar('f24d0e0c15327182dda64a93892352a39792fc347182c263c72ee32045638a70@group.calendar.google.com')
  return result.id
end

service = Google::Apis::CalendarV3::CalendarService.new
service.authorization = authorize_google_calendar

calendar_id = get_calendar(service)

url = 'https://www.fpb.pt/equipa/equipa_52834/'
games = extract_games(url)

add_to_google_calendar(service, calendar_id, games)

# games.each do |game|
#   puts "Date: #{game[:date]}"
#   puts "Time: #{game[:time]}"
#   puts "Teams: #{game[:teams].join(' vs ')}"
#   puts "Location: #{game[:location]}"
#   puts "Competition: #{game[:competition]}"
#   puts "---"
# end
