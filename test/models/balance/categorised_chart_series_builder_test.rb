require "test_helper"

class Balance::CategorisedChartSeriesBuilderTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to("2025-08-30")
  end

  test "monthly categorised entries with 12 month rolling average" do
    account = accounts(:depository)
    account.entries.destroy_all
    category = Category.create!(name: "Food & Dining", family: account.family)

    # Entries
    create_transaction(account:, amount: -450, date: Date.new(2024, 4, 22), category:, currency: "PLN")
    create_transaction(account:, amount: -150, date: Date.new(2024, 6, 15), category:, currency: "PLN")
    create_transaction(account:, amount: -350, date: Date.new(2025, 3, 31), category:, currency: "PLN")
    create_transaction(account:, amount: -1250, date: Date.new(2025, 4, 1), category:, currency: "PLN")
    create_transaction(account:, amount: -200, date: Date.new(2025, 6, 30), category:, currency: "PLN")
    create_transaction(account:, amount: -100, date: Date.new(2025, 8, 30), category:, currency: "PLN")

    builder = Balance::CategorisedChartSeriesBuilder.new(
      account_ids: [ account.id ],
      category_ids: [ category.id ],
      currency: "PLN",
      period: Period.from_key("last_365_days"),
      interval: "1 month",
      favorable_direction: "down"
    )

    assert_equal 12, builder.balance_series.values.size # 12 months even if 11 of them show 0 expenses

    expected = [
      0.0, -50.0, # includes previous entries: -150 on 2024-06-15 and -450 on 2024-04-22
      0.0, -50.0,
      0.0, -50.0,
      0.0, -50.0,
      0.0, -50.0,
      0.0, -50.0,
   -350.0, -79.16,
  -1250.0, -145.83,
      0.0, -145.83,
   -200.0, -150.0,
      0.0, -150.0,
   -100.0, -158.33
    ]

    assert_equal expected, builder.balance_series.values.map { |v| [ v.value.amount, v.trend.previous.amount ] }.flatten
  end
end
