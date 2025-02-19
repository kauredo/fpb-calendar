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

TEAM_HEADERS = %w[id name age gender season url]
GAME_HEADERS = %w[name age gender date time teams result location competition season link]
EXCLUDED_TERMS = Set.new(["venc", "º", "designar", "3x3"]) # Precompute excluded terms for faster lookup

def load_teams_csv_data
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

  teams = []
  CSV.foreach('data/teams.csv', col_sep: ';') do |row|
    team = TEAM_HEADERS.zip(row).to_h

    # Use Set lookup instead of array iteration
    next if EXCLUDED_TERMS.any? { |term| team["name"].to_s.downcase.include?(term) }

    # Simple season check
    valid_season = team["season"] == current_season || (extra_season && team["season"] == extra_season)

    teams << team if valid_season
  end
  teams
end

def load_games_csv_data(teams_cache)
  games_by_team = {}

  # Create efficient lookup hash for teams
  teams_lookup = teams_cache.group_by { |team|
    [
      team["name"].downcase,
      team["age"].downcase,
      team["gender"].downcase,
      team["season"].downcase
    ].join("\0")
  }

  CSV.foreach('data/games.csv', col_sep: ';') do |row|
    game = GAME_HEADERS.zip(row).to_h

    # Create quick lookup key
    lookup_key = [
      game["name"].downcase,
      game["age"].downcase,
      game["gender"].downcase,
      game["season"].downcase
    ].join("\0")

    # Find matching teams efficiently
    matching_teams = teams_lookup[lookup_key]
    next unless matching_teams

    matching_teams.each do |team|
      (games_by_team[team["id"].to_i] ||= []) << game
    end
  end

  games_by_team
end

# Load data once when the app starts
$teams_cache = ENV['APP_ENV'] == 'production' ? [] : load_teams_csv_data
$games_cache = ENV['APP_ENV'] == 'production' ? {} : load_games_csv_data($teams_cache)
$games_cache_timestamps = {}

# Homepage with the form
get '/' do
  erb :index
end

get '/calendar/:id' do
  @team_id = params[:id].to_i
  @team = $teams_cache.find { |team| team['id'].to_i == @team_id }

  # Check if data exists and if it's older than 1 hour
  if !$games_cache[@team_id] || Time.now - ($games_cache_timestamps[@team_id] || Time.at(0)) > ENV['CACHE_EXPIRATION'].to_i
    puts "Scraping new data for team #{@team_id}"
    scraper = FpbScraper.new("https://www.fpb.pt/equipa/equipa_#{@team_id}")
    data = scraper.fetch_team_data(results: true)
    games = data[:games]

    # Update the cache timestamp
    $games_cache_timestamps[@team_id] = Time.now
  else
    puts "Using cached data for team #{@team_id}"
    games = $games_cache[@team_id]
  end

  cached_games = $games_cache[@team_id] || []
  tmp = games.map do |game|
    cached_game = cached_games.find { |cached_game| cached_game['link'] == game[:link] }

    if cached_game
      merged_game = cached_game.merge(game.transform_keys(&:to_s)) do |key, game_value, cached_value|
        # Reject arrays and Date instances
        if [game_value, cached_value].any? { |v| v.is_a?(Array) || v.is_a?(Date) }
          next game_value # Keep the existing game value (or nil if it was nil)
        end

        # Prefer non-nil and non-empty values
        tmp_value = game_value.nil? || game_value == "" ? cached_value : game_value
        tmp_value = '' if tmp_value.nil?

        tmp_value
      end
    else
      merged_game = game.transform_keys(&:to_s).transform_values do |value|
        case value
        when Date
          value.to_s
        when Array
          value.join(' vs ')
        when nil
          ''
        else
          value
        end
      end
    end

    merged_game
  end
  $games_cache[@team_id] = tmp

  @team_name = if @team
    "#{@team['name']} (#{ @team['age'] } #{ @team['gender'].chars.first })"
  else
    "Equipa não encontrada"
  end

  erb :calendar
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

  # Base URL of the site
  base_url = "https://fpb-calendar.fly.dev"

  # Create array of all URLs
  urls = [
    base_url, # Homepage
  ]

  # Add all team calendar URLs
  $teams_cache.each do |team|
    urls << "#{base_url}/calendar/#{team['id']}"
  end

  # Generate sitemap XML
  builder = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"]

    urls.each do |url|
    builder << "  <url>"
    builder << "    <loc>#{url}</loc>"
    builder << "    <lastmod>#{Time.now.utc.iso8601}</lastmod>"
    builder << "    <changefreq>daily</changefreq>"
    builder << "    <priority>#{url == base_url ? '1.0' : '0.8'}</priority>"
    builder << "  </url>"
  end

  builder << "</urlset>"
  builder.join("\n")
end

# API endpoint to get teams
get '/api/teams' do
  puts "[GET] /api/teams"
  content_type :json
  $teams_cache.to_json
end

# Manually refresh the cache (only when needed)
get '/api/refresh' do
  puts "[GET] /api/refresh"
  content_type :json
  $teams_cache = load_teams_csv_data
  $games_cache = load_games_csv_data($teams_cache)
  $games_cache_timestamps = {}
  { teams: $teams_cache, games: $games_cache }.to_json
end

get '/api/teams/:id' do
  content_type :json
  id = params[:id].to_i
  puts "[GET] /api/teams/#{id}"
  team = $teams_cache.find { |team| team['id'].to_i == id }
  games = $games_cache[id] || []
  { team: team, games: games }.to_json
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
