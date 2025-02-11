# services/fpb_scraper.rb
require 'uri'
require 'net/http'
require 'openssl'
require 'nokogiri'
require 'date'

class FpbScraper
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
  }.freeze

  attr_reader :url

  def initialize(url)
    @url = url.sub('https://www.fpb.pt/equipa/', '').sub('/', '').prepend('https://www.fpb.pt/equipa/')
  end

  def fetch_team_data
    html = fetch_page
    doc = Nokogiri::HTML(html)

    {
      team_name: extract_team_name(doc),
      games: parse_games(doc)
    }
  end

  private

  def fetch_page
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    max_redirects = 5
    redirects = 0

    while redirects < max_redirects
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      if response.code.to_i == 301 || response.code.to_i == 302
        uri = URI.parse(response['Location'])
        redirects += 1
      else
        return response.body
      end
    end

    raise "Too many redirects for URL: #{url}"
  end

  def extract_team_name(doc)
    doc.css('div.team-nome').text.strip
  end

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

  def parse_game_details(day_wrapper, date)
    games = []
    game_wrappers = day_wrapper.css('div.game-wrapper')

    game_wrappers.each do |game_wrapper|
      time_text = game_wrapper.at_css('div.hour')&.text&.strip || ''
      teams = game_wrapper.css('span.fullName').map(&:text).map(&:strip)
      location_element = game_wrapper.at_css('div.location-wrapper')
      competition = location_element&.css('div.competition')&.text&.strip
      location = location_element&.text&.strip.split("\r\n").map(&:strip).reject(&:empty?) - [competition]
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
end
