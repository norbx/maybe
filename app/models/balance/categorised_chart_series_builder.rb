class Balance::CategorisedChartSeriesBuilder
  def initialize(account_ids:, category_ids:, currency:, period: Period.last_365_days, interval: "1 month", favorable_direction: "up")
    @account_ids = account_ids
    @category_ids = category_ids
    @currency = currency
    @period = period
    @interval = interval
    @favorable_direction = favorable_direction
  end

  def balance_series
    build_series
  rescue => e
    Rails.logger.error "Categorised balance series error: #{e.message} for accounts #{@account_ids}"
    raise
  end

  private
    attr_reader :account_ids, :category_ids, :currency, :period, :favorable_direction

    def interval
      @interval || period.interval
    end

    def build_series
      values = query_data.map do |datum|
        Series::Value.new(
          date: datum.date,
          date_formatted: I18n.l(datum.date, format: :long),
          value: Money.new(datum.current, currency),
          trend: Trend.new(
            current: Money.new(datum.current, currency),
            previous: Money.new(datum.moving_average, currency),
            favorable_direction: favorable_direction
          )
        )
      end

      Series.new(
        start_date: period.start_date,
        end_date: period.end_date,
        interval: interval,
        values: values,
        favorable_direction: favorable_direction
      )
    end

    def query_data
      @query_data ||= Balance.find_by_sql([
        query,
        {
          account_ids: account_ids,
          category_ids: category_ids,
          start_date: period.start_date,
          end_date: period.end_date,
          interval: interval,
          sign_multiplier: sign_multiplier
        }
      ])
    rescue => e
      Rails.logger.error "Query data error: #{e.message} for accounts #{account_ids}, period #{period.start_date} to #{period.end_date}"
      raise
    end

    # Since the query aggregates the *net* of assets - liabilities, this means that if we're looking at
    # a single liability account, we'll get a negative set of values.  This is not what the user expects
    # to see.  When favorable direction is "down" (i.e. liability, decrease is "good"), we need to invert
    # the values by multiplying by -1.
    def sign_multiplier
      favorable_direction == "down" ? -1 : 1
    end

    def query
      <<~SQL
        WITH dates AS (
          SELECT generate_series(DATE :start_date, DATE :end_date, :interval::interval)::date AS date
          UNION DISTINCT
          SELECT :end_date::date  -- Ensure end date is included
        )
        SELECT
          d.date,
          cat.category_name,
          TRUNC(SUM(en.amount), 2) current,
          TRUNC(AVG(SUM(en.amount)) OVER(ORDER BY d.date ROWS BETWEEN 12 PRECEDING AND CURRENT ROW), 2) moving_average
        FROM dates d
        CROSS JOIN accounts
        LEFT JOIN LATERAL (
          SELECT e.amount, t.category_id category_id
          FROM entries e
          LEFT JOIN transactions t
          ON t.id = e.entryable_id
          WHERE e.account_id = accounts.id
            AND e.date < d.date
            AND e.date >= (d.date - INTERVAL :interval)
            AND e.entryable_type = 'Transaction'
        ) en ON TRUE
        LEFT JOIN LATERAL (
          SELECT c.id id, c.name category_name
          FROM categories c
          WHERE c.id = en.category_id
        ) cat ON TRUE
        WHERE accounts.id = ANY(array[:account_ids]::uuid[])
        AND cat.id = ANY(array[:category_ids]::uuid[])
        GROUP BY d.date, cat.category_name
        ORDER BY d.date
      SQL
    end
end
