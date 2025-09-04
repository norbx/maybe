class BalanceSheet::CategorisedSeriesBuilder
  def initialize(family)
    @family = family
  end

  def categorised_series(period: Period.last_365_days, current_category_id:)
    Rails.cache.fetch(cache_key(period, current_category_id)) do
      builder = Balance::CategorisedChartSeriesBuilder.new(
        account_ids: visible_account_ids,
        category_ids: Array(current_category_id),
        currency: family.currency,
        period: period,
        interval: "1 month",
        favorable_direction: "down"
      )

      builder.balance_series
    end
  end

  private
    attr_reader :family

    def visible_account_ids
      @visible_account_ids ||= family.accounts.visible.with_attached_logo.pluck(:id)
    end

    def cache_key(period, category_id)
      key = [
        "balance_sheet_categorised_series",
        period.start_date,
        period.end_date,
        category_id
      ].compact.join("_")

      family.build_cache_key(
        key,
        invalidate_on_data_updates: true
      )
    end
end
