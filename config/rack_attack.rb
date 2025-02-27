# frozen_string_literal: true

module Rack
  class Attack
    # Throttle requests by IP address (5 requests per minute)
    throttle('req/ip', limit: 5, period: 60, &:ip)
  end
end
