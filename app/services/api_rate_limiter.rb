class ApiRateLimiter
  # Rate limit tiers (requests per hour)
  RATE_LIMITS = {
    standard: 100,
    premium: 1000,
    enterprise: 10000
  }.freeze

  DEFAULT_TIER = :standard

  def initialize(api_key)
    @api_key = api_key
  end

  # Check if the API key has exceeded its rate limit
  def rate_limit_exceeded?
    current_count >= rate_limit
  end

  # Increment the request count for this API key
  def increment_request_count!
    window_start = current_window_start
    expires_at = 2.hours.from_now

    # Find or create the bucket for this hour window
    bucket = ApiRateLimitBucket.find_or_create_by!(
      api_key_id: @api_key.id,
      window_start: window_start
    ) do |b|
      b.expires_at = expires_at
      b.request_count = 0
    end

    # Atomically increment the request count
    bucket.increment!(:request_count)
  end

  # Get current request count within the current hour
  def current_count
    window_start = current_window_start

    bucket = ApiRateLimitBucket.find_by(
      api_key_id: @api_key.id,
      window_start: window_start
    )

    bucket&.request_count || 0
  end

  # Get the rate limit for this API key's tier
  def rate_limit
    tier = determine_tier
    RATE_LIMITS[tier]
  end

  # Calculate seconds until the rate limit resets
  def reset_time
    current_time = Time.current.to_i
    next_window = ((current_time / 3600) + 1) * 3600
    next_window - current_time
  end

  # Get detailed usage information
  def usage_info
    {
      current_count: current_count,
      rate_limit: rate_limit,
      remaining: [rate_limit - current_count, 0].max,
      reset_time: reset_time,
      tier: determine_tier
    }
  end

  # Class method to get usage for an API key without incrementing
  def self.usage_for(api_key)
    limit(api_key).usage_info
  end

  def self.limit(api_key)
    if Rails.application.config.app_mode.self_hosted?
      # Use NoopApiRateLimiter for self-hosted mode
      # This means no rate limiting is applied
      NoopApiRateLimiter.new(api_key)
    else
      new(api_key)
    end
  end

  private

    def current_window_start
      (Time.current.to_i / 3600) * 3600
    end

    def determine_tier
      # For now, all API keys are standard tier
      # This can be extended later to support different tiers based on user subscription
      # or API key configuration
      DEFAULT_TIER
    end
end
