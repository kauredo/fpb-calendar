class Rack::Attack
  # Throttle requests by IP address (5 requests per minute)
  throttle('req/ip', limit: 5, period: 60) do |req|
    req.ip
  end
end
