require "test_helper"

class Balance::CategorisedChartSeriesBuilderTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to("2025-08-30")
  end

  test "monthly categorised entries with month to month trend" do
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

    assert_equal 13, builder.balance_series.values.size

    expected = [
      0.0,  150.0,
      0.0,    0.0,
      0.0,    0.0,
      0.0,    0.0,
      0.0,    0.0,
      0.0,    0.0,
      0.0,    0.0,
      0.0,    0.0,
   -350.0, -350.0,
  -1250.0, -900.0,
      0.0, 1250.0,
   -200.0, -200.0,
      0.0,  200.0 # Latest month taken into account is July, as August is not over yet
    ]

    assert_equal expected, builder.balance_series.values.map { |v| [ v.value.amount.to_f, v.trend.value.amount.to_f ] }.flatten
  end
end
