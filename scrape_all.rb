require_relative 'services/bulk_fpb_scraper'

scraper = BulkFpbScraper.new(start_id: 1, end_id: 100)
scraper.scrape_all
