class ApiRateLimitBucket < ApplicationRecord
  belongs_to :api_key

  validates :window_start, presence: true, uniqueness: { scope: :api_key_id }
  validates :request_count, numericality: { greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true

  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :for_api_key, ->(api_key) { where(api_key: api_key) }
  scope :for_window, ->(window_start) { where(window_start: window_start) }

  def self.cleanup_expired
    expired.delete_all
  end
end