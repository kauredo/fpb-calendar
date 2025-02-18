require 'sinatra'
require 'rack/attack'
require 'csv'
require 'pry'
require_relative 'fpb_calendar'
use Rack::Attack

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
set :hosts, ['fpb-calendar.fly.dev', 'localhost'] # Sinatra will enforce allowed hosts
set :protection, :except => :host # Disable Rack::Protection HostAuthorization

HEADERS = %w[id name age gender season url]

def load_csv_data
  teams = []
  CSV.foreach('data/teams.csv', col_sep: ';') do |row|
    team = HEADERS.zip(row).to_h

    # Check if name contains any excluded terms
    excluded_terms = ["venc", "º", "designar", "3x3"]
    name_has_excluded_term = excluded_terms.any? { |term| team["name"].to_s.downcase.include?(term) }

    # Check if season is current or previous
   current_year = Time.now.year
    month = Time.now.month

    if month < 8 # Before August (e.g., July 2025 → still in 2024-2025)
      current_season = "#{current_year - 1}-#{current_year}" # "2024-2025" if in July 2025
      extra_season = "#{current_year}-#{current_year}"       # "2025-2025" if in July 2025
    else # August or later (e.g., October 2025 → new season starts)
      current_season = "#{current_year}-#{current_year + 1}" # "2025-2026" if in October 2025
      extra_season = nil
    end

    # Check if the team's season matches the required seasons
    valid_season = team["season"] == current_season || team["season"] == extra_season

    # Add team if it passes both checks
    if !name_has_excluded_term && valid_season
      teams << team
    end
  end
  teams
end


before do
  @teams ||= load_csv_data
end

# Homepage with the form
get '/' do
  erb :index
end

get '/health' do
  'OK'
end

# robots.txt for SEO
get '/robots.txt' do
  content_type 'text/plain'
  """
  User-agent: *
  Disallow: /health
  Sitemap: https://fpb-calendar.fly.dev/sitemap.xml
  """
end

# Dynamic sitemap generation
get '/sitemap.xml' do
  content_type 'application/xml'
  urls = [
    "https://fpb-calendar.fly.dev/",
  ]

  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{urls.map { |url| "<url><loc>#{url}</loc><lastmod>#{Time.now.utc.iso8601}</lastmod></url>" }.join}\n
    </urlset>
  XML
end

get '/api/teams' do
  content_type :json
  @teams.to_json
end

# Handle form submissions
post '/invite' do
  email = params[:email]
  team_url = params[:team_url]

  # Ensure the required parameters are provided
  if email.nil? || email.strip.empty? || team_url.nil? || team_url.strip.empty? || !team_url.start_with?('https://www.fpb.pt/equipa/')
    @error_message = 'Por favor, forneça um endereço de e-mail e um URL de equipa válido.'
    status 400
    return erb :error
  end

  begin
    # Initialize the FpbCalendar instance
    calendar = FpbCalendar.new(team_url)

    # Find or create a calendar
    calendar_id = calendar.find_or_create_calendar

    # Share the calendar with the provided email
    calendar.share_calendar_with_email(calendar_id, email)

    # Add games to the calendar
    calendar.add_games_to_calendar(calendar_id)
    calendar.remove_stale_events(calendar_id)

    @team_name = calendar.team_data[:team_name]
    @calendar_link = calendar.calendar_link(calendar_id)

    calendar.cleanup

    status 200
    erb :success
  rescue StandardError => e
    @error_message = e.message
    status 500
    erb :error
  end
end
