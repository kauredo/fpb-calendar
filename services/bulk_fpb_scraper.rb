# scrape.rb
require_relative 'fpb_scraper'
require 'csv'
require 'logger'
require 'parallel'
require 'fileutils'
require 'json'
require 'set'
require 'pry'

class BulkFpbScraper
  BATCH_SIZE = 50
  MAX_RETRIES = 3
  MAX_EMPTY_IN_ROW = 20
  DELAY = 1 # seconds between requests
  BASE_URL = 'https://www.fpb.pt/equipa/equipa_'.freeze
  OUTPUT_DIR = 'data'.freeze

  def initialize(start_id: 1, end_id: nil)
    @start_id = start_id
    @end_id = end_id
    setup_directories
    setup_logger
    @scraped_ids = load_scraped_ids
    @empty_ids = load_empty_ids
  end

  def scrape_all
    log("Starting bulk scrape from ID #{@start_id}" + (@end_id ? " to #{@end_id}" : ""))

    current_id = @start_id
    empty_team_count = 0 # Counter for consecutive empty teams

    loop do
      # Check if we've reached the end_id
      if @end_id && current_id > @end_id
        log("Reached specified end ID: #{@end_id}")
        break
      end

      batch = generate_next_batch(current_id)
      if batch.empty?
        current_id += BATCH_SIZE
        # log("No new IDs to process, might be at the end")
        # break
      else
        results = process_batch(batch)

        # Check results and update empty_team_count
        last_results = results.sort_by { |r| r[:id] }.last(5)
        if last_results.all? { |r| r[:success] && r[:data][:team_name].empty? }
          empty_team_count += 1
          log("Found #{empty_team_count} consecutive empty teams, might be at the end")
          break if empty_team_count >= MAX_EMPTY_IN_ROW && !@end_id # Only break for empty teams if no end_id specified
        else
          empty_team_count = 0
        end

        current_id = batch.max + 1
      end
    end

    log("Scraping completed. Last processed ID: #{current_id - 1}")
    generate_summary
  end

  private

  def log(msg, level = :info)
    @logger.send(level, msg)
    puts msg
  end

  def setup_directories
    FileUtils.mkdir_p(OUTPUT_DIR)
    FileUtils.mkdir_p('log')
  end

  def setup_logger
    @logger = Logger.new('log/scraper.log')
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, _, msg|
      "[#{datetime}] #{severity}: #{msg}\n"
    end
  end

  def load_scraped_ids
    # Load scraped IDs from first column of teams.csv
    if File.exist?("#{OUTPUT_DIR}/teams.csv")
      CSV.read("#{OUTPUT_DIR}/teams.csv", col_sep: ';').map { |row| row.first.to_i }.to_set
    else
      Set.new
    end
  end

  def load_empty_ids
    if File.exist?("#{OUTPUT_DIR}/empty_ids.json")
      Set.new(JSON.parse(File.read("#{OUTPUT_DIR}/empty_ids.json")))
    else
      Set.new
    end
  end

  def save_empty_ids
    File.write("#{OUTPUT_DIR}/empty_ids.json", JSON.pretty_generate(@empty_ids.to_a))
  end

  def generate_next_batch(current_id)
    end_of_batch = if @end_id
      [current_id + BATCH_SIZE - 1, @end_id].min
    else
      current_id + BATCH_SIZE - 1
    end

    batch = (current_id..end_of_batch).to_a
    # Filter out already scraped IDs
    batch.reject { |id| @scraped_ids.include?(id) || @empty_ids.include?(id) }
  end

  def process_batch(batch)
    log("Processing batch: IDs #{batch.first} to #{batch.last}")

    results = Parallel.map(batch, in_threads: 4) do |id|
      process_team(id)
    end

    # Save successful results
    results.each do |result|
      next unless result && result[:success]

      if result[:data][:team_name].empty?
        log("Empty team found for ID #{result[:id]}")
        @empty_ids.add(result[:id])
      else
        save_team_data(result[:id], result[:data])
        @scraped_ids.add(result[:id])
      end

    end

    save_empty_ids
    results
  end

  def process_team(id)
    url = "#{BASE_URL}#{id}"
    return { success: true, id: id, data: nil } if @scraped_ids.include?(id) || @empty_ids.include?(id)

    retries = 0

    begin
      log("Scraping team ID: #{id}")
      scraper = FpbScraper.new(url)
      team_data = scraper.fetch_team_data(results: true)

      sleep DELAY

      { success: true, id: id, data: team_data }
    rescue => e
      retries += 1
      if retries <= MAX_RETRIES
        log("Retry #{retries}/#{MAX_RETRIES} for team #{id}: #{e.message}", :warn)
        sleep(DELAY * retries)
        retry
      else
        log("Failed to scrape team #{id} after #{MAX_RETRIES} retries: #{e.message}", :error)
        { success: false, id: id }
      end
    end
  end

  def save_team_data(id, team_data)
    return if team_data[:team_name].empty?

    # Save team info
    CSV.open("#{OUTPUT_DIR}/teams.csv", 'a+', col_sep: ';') do |csv|
      name = team_data[:team_name]
      age_group = team_data[:team_info][:age_group]
      gender = team_data[:team_info][:gender]
      season = team_data[:games].first&.dig(:season)
      url = team_data[:team_info][:url]

      csv << [id, name, age_group, gender, season, url]
    end

    # Save games
    CSV.open("#{OUTPUT_DIR}/games.csv", 'a+', col_sep: ';') do |csv|
      team_data[:games].each do |game|
        csv << [
          team_data[:team_name],
          game[:age_group],
          game[:gender],
          game[:date],
          game[:time],
          game[:teams].join(' vs '),
          game[:result],
          game[:location],
          game[:competition],
          game[:season],
          game[:link]
        ]
      end
    end
  end

  def generate_summary
    summary = {
      total_teams_processed: @scraped_ids.size,
      last_successful_id: @scraped_ids.max,
      first_successful_id: @scraped_ids.min,
      timestamp: Time.now
    }

    File.write("#{OUTPUT_DIR}/summary.json", JSON.pretty_generate(summary))
    log("Summary generated. Total teams processed: #{summary[:total_teams_processed]}")
  end
end
