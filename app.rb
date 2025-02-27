# frozen_string_literal: true

require 'sinatra'
require 'rack/attack'
require 'csv'
require 'pry'
require_relative 'fpb_calendar'
require_relative 'lib/memory_bound_cache'
use Rack::Attack

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
set :hosts, ['fpb-calendar.fly.dev', 'localhost'] # Sinatra will enforce allowed hosts
set :protection, except: :host # Disable Rack::Protection HostAuthorization

TEAM_HEADERS = %w[id name age gender season url].freeze
GAME_HEADERS = %w[name age gender date time teams result location competition season link].freeze
EXCLUDED_TERMS = Set.new(%w[venc º designar 3x3]) # Precompute excluded terms for faster lookup

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
    next if EXCLUDED_TERMS.any? { |term| team['name'].to_s.downcase.include?(term) }

    # Simple season check
    valid_season = team['season'] == current_season || (extra_season && team['season'] == extra_season)

    teams << team if valid_season
  end
  teams
end

# Load games for a specific team only
def load_games_for_team(team_id)
  team = $teams_cache.find { |t| t['id'].to_i == team_id.to_i }
  return [] unless team

  # Create lookup info for this team
  team_lookup = [
    team['name'].downcase,
    team['age'].downcase,
    team['gender'].downcase,
    team['season'].downcase
  ].join("\0")

  games = []
  CSV.foreach('data/games.csv', col_sep: ';') do |row|
    game = GAME_HEADERS.zip(row).to_h

    # Create quick lookup key for this game
    game_lookup = [
      game['name'].downcase,
      game['age'].downcase,
      game['gender'].downcase,
      game['season'].downcase
    ].join("\0")

    # Add to games if it matches
    games << game if game_lookup == team_lookup
  end

  games
end

# Load teams data at startup (required for API/UI)
$teams_cache = load_teams_csv_data
# Use memory-bound cache for games instead of loading all at once
$games_cache = MemoryBoundCache.new(30) # Limit to 30 teams' worth of games
$games_cache_timestamps = {}

# Homepage with the form
get '/' do
  erb :index
end

get '/calendar/:id' do
  @team_id = params[:id].to_i
  @team = $teams_cache.find { |team| team['id'].to_i == @team_id }
  # Return 404 if team not found
  unless @team
    status 404
    @team_name = 'Equipa não encontrada'
    return erb :error
  end

  begin
    # Check if data exists and if it's older than the expiration time
    cache_expiration = ENV['CACHE_EXPIRATION'].to_i || 3600 # Default to 1 hour if not set

    # Use the timestamp from the cache object itself, not a separate hash
    if !$games_cache.key?(@team_id) ||
       Time.now - ($games_cache.timestamp(@team_id) || Time.at(0)) > cache_expiration
      puts "Getting fresh data for team #{@team_id}"

      # Load CSV games for this team
      csv_games = load_games_for_team(@team_id)

      # Then scrape web data
      scraper = FpbScraper.new("https://www.fpb.pt/equipa/equipa_#{@team_id}")
      data = scraper.fetch_team_data(results: true)
      scraped_games = data[:games]

      # Combine scraped games with CSV games
      games = scraped_games.dup

      # Add CSV games that aren't in scraped games
      csv_games.each do |csv_game|
        csv_game = csv_game.transform_keys(&:to_s)
        next if games.any? { |g| g[:link] == csv_game['link'] }

        # Convert string keys to symbols to match scraped games format
        symbolized_game = {}
        csv_game.each { |k, v| symbolized_game[k.to_sym] = v }
        games << symbolized_game
      end

      # Get any existing cached games
      cached_games = $games_cache[@team_id] || []

      # Process and transform games
      merged_games = games.map do |game|
        # Look for matching game in the cache
        cached_game = cached_games.find { |cg| cg['link'] == game[:link] }

        merged_game = if cached_game
                        # Merge with existing cached game
                        cached_game.merge(game.transform_keys(&:to_s)) do |_key, game_value, cached_value|
                          # Reject arrays and Date instances
                          if [game_value, cached_value].any? { |v| v.is_a?(Array) || v.is_a?(Date) }
                            next game_value # Keep the existing game value
                          end

                          # Prefer non-nil and non-empty values
                          tmp_value = game_value.nil? || game_value == '' ? cached_value : game_value
                          tmp_value = '' if tmp_value.nil?
                          tmp_value
                        end
                      else
                        # Transform new game
                        game.transform_keys(&:to_s).transform_values do |value|
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

      # Store in cache once (not twice)
      $games_cache[@team_id] = merged_games
      # No need to update timestamp separately - it's handled in the cache class
    end

    @team_name = "#{@team['name']} (#{@team['age']} #{@team['gender']})"
    @current_season = @team['season']
    @last_updated = $games_cache.timestamp(@team_id)

    # Set cache headers for browsers
    cache_control :public, :must_revalidate, max_age: 3600 # Cache for 1 hour
    last_modified @last_updated if @last_updated
    erb :calendar
  rescue StandardError => e
    puts "Error fetching calendar data: #{e.message}"
    status 500
    @error_message = 'Ocorreu um erro ao carregar os dados da equipa. Por favor, tente novamente mais tarde.'
    erb :error
  end
end

get '/health' do
  'OK'
end

# robots.txt for SEO
get '/robots.txt' do
  content_type 'text/plain'
  "
  User-agent: *
  Disallow: /health
  Sitemap: https://fpb-calendar.fly.dev/sitemap.xml
  "
end

# Dynamic sitemap generation
get '/sitemap.xml' do
  content_type 'application/xml'

  # Base URL of the site
  base_url = 'https://fpb-calendar.fly.dev'

  # Create array of all URLs
  urls = [
    base_url # Homepage
  ]

  # Add all team calendar URLs
  $teams_cache.each do |team|
    urls << "#{base_url}/calendar/#{team['id']}"
  end

  # Generate sitemap XML
  builder = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']

  urls.each do |url|
    builder << '  <url>'
    builder << "    <loc>#{url}</loc>"
    builder << "    <lastmod>#{Time.now.utc.iso8601}</lastmod>"
    builder << '    <changefreq>daily</changefreq>'
    builder << "    <priority>#{url == base_url ? '1.0' : '0.8'}</priority>"
    builder << '  </url>'
  end

  builder << '</urlset>'
  builder.join("\n")
end

# API endpoint to get teams
get '/api/teams' do
  puts '[GET] /api/teams'
  content_type :json
  $teams_cache.to_json
end

# Manually refresh the cache (only when needed)
get '/api/refresh' do
  puts '[GET] /api/refresh'
  content_type :json
  $teams_cache = load_teams_csv_data
  $games_cache = MemoryBoundCache.new(30) # Reset the games cache

  {
    memory_usage_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024,
    games_cache_size: $games_cache.size,
    games_cache_keys: $games_cache.keys,
    teams_count: $teams_cache.size
  }.to_json
end

get '/api/teams/:id' do
  content_type :json
  id = params[:id].to_i
  puts "[GET] /api/teams/#{id}"
  team = $teams_cache.find { |cached_team| cached_team['id'].to_i == id }

  # Load games on demand if needed
  $games_cache[id] = load_games_for_team(id) unless $games_cache[id]

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

# Add a debug endpoint to see memory usage (optional)
get '/api/debug' do
  content_type :json
  {
    memory_usage_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024,
    games_cache_size: $games_cache.size,
    games_cache_keys: $games_cache.keys,
    teams_count: $teams_cache.size
  }.to_json
end
