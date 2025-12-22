class CleanupExpiredRateLimitBucketsJob < ApplicationJob
  queue_as :low_priority

  def perform
    deleted_count = ApiRateLimitBucket.cleanup_expired
    Rails.logger.info("Cleaned up #{deleted_count} expired rate limit buckets")
  end
end
