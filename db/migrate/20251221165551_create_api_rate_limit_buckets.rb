class CreateApiRateLimitBuckets < ActiveRecord::Migration[8.0]
  def change
    create_table :api_rate_limit_buckets do |t|
      t.references :api_key, null: false, foreign_key: true, index: false, type: :uuid
      t.bigint :window_start, null: false
      t.integer :request_count, default: 0, null: false
      t.datetime :expires_at, null: false

      t.timestamps

      t.index [:api_key_id, :window_start], unique: true, name: "index_rate_limit_buckets_on_api_key_and_window"
      t.index :expires_at, name: "index_rate_limit_buckets_on_expires_at"
    end
  end
end
