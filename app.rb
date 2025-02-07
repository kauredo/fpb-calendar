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

    status 200
    erb :success
  rescue StandardError => e
    @error_message = e.message
    status 500
    erb :error
  end
end
