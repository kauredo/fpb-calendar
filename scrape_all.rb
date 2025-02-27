# frozen_string_literal: true

require_relative 'services/bulk_fpb_scraper'

scraper = BulkFpbScraper.new(start_id: 1)
scraper.scrape_all
