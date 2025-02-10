require 'sinatra'
require 'rack/attack'
require_relative 'fpb_calendar'
use Rack::Attack

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
set :hosts, ['fpb-calendar.fly.dev', 'localhost'] # Sinatra will enforce allowed hosts
set :protection, :except => :host # Disable Rack::Protection HostAuthorization

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
