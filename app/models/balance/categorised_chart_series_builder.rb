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
            previous: Money.new(datum.previous, currency),
            favorable_direction: favorable_direction
          ),
          moving_average: Money.new(datum.moving_average, currency),
          moving_average_trend: Trend.new(
            current: Money.new(datum.moving_average, currency),
            previous: Money.new(datum.previous_moving_average, currency),
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
          SELECT (date_trunc('month', (gs)) + INTERVAL '1 month - 1 day') AS date
          FROM generate_series(
            date_trunc('month', DATE :start_date::date - INTERVAL '13 months'),
            date_trunc('month', DATE :end_date::date - INTERVAL '1 month'),
            :interval::interval
          ) AS gs
        ),
        date_categories AS (
          SELECT d.date, c.id AS category_id, c.name AS category_name
          FROM dates d
          CROSS JOIN categories c
          WHERE c.id = ANY(array[:category_ids]::uuid[])
        ),
        aggregated AS (
          SELECT
            dc.date date,
            dc.category_name,
            COALESCE(TRUNC(SUM(en.amount), 2), 0) current
          FROM date_categories dc
          CROSS JOIN accounts a
          LEFT JOIN LATERAL (
            SELECT e.amount
            FROM entries e
            LEFT JOIN transactions t
              ON t.id = e.entryable_id
            WHERE e.account_id = a.id
              AND t.category_id = dc.category_id
              AND e.date <= (date_trunc('month', dc.date) + INTERVAL '1 month - 1 day')
              AND e.date > (date_trunc('month', dc.date - INTERVAL :interval) + INTERVAL '1 month - 1 day')
              AND e.entryable_type = 'Transaction'
          ) en ON TRUE
          WHERE a.id = ANY(array[:account_ids]::uuid[])
          GROUP BY dc.date, category_name
        ),
        with_previous AS (
          SELECT *,
                LAG(current) OVER(ORDER BY date) AS previous
          FROM aggregated
        ),
        with_ma AS (
          SELECT date,
                category_name,
                current,
                previous,
                TRUNC(AVG(current) OVER(ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 2) moving_average
          FROM with_previous
        ),
        with_previous_ma AS (
          SELECT *,
                LAG(moving_average) OVER(ORDER BY date) AS previous_moving_average
          FROM with_ma
        ),
        latest_13 AS (
          SELECT *
          FROM with_previous_ma
          WHERE date >= (date_trunc('month', (:start_date::date - INTERVAL '12 months')) + INTERVAL '1 month - 1 day')
            AND date <= (date_trunc('month', :end_date::date) + INTERVAL '1 month - 1 day')
          ORDER BY date DESC
          LIMIT 13
        )
        SELECT *
        FROM latest_13
        ORDER BY date
      SQL
    end
end
