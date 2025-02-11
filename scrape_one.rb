require_relative 'services/bulk_fpb_scraper'

team_id = ARGV[0]&.to_i

unless team_id && team_id > 0
  puts "Please provide a team ID as an argument"
  puts "Usage: ruby scrape_one.rb TEAM_ID"
  exit 1
end

scraper = BulkFpbScraper.new(start_id: team_id, end_id: team_id)
scraper.scrape_all
