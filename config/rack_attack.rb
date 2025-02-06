class Rack::Attack
  # Throttle requests by IP address (5 requests per minute)
  throttle('req/ip', limit: 2, period: 60) do |req|
    req.ip
  end

  # Blocklist specific IPs (optional)
  blocklist('block bad IP') do |req|
    ['192.168.1.100', '10.0.0.1'].include?(req.ip)
  end

  # Whitelist specific IPs (optional)
  safelist('allow local IPs') do |req|
    ['127.0.0.1', '::1'].include?(req.ip)
  end
end
