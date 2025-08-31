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
          SELECT generate_series(DATE :start_date - (:interval::interval * 11), DATE :end_date, :interval::interval)::date AS date
          UNION DISTINCT
          SELECT :end_date::date  -- Ensure end date is included
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
              AND e.date < dc.date
              AND e.date >= (dc.date - INTERVAL :interval)
              AND e.entryable_type = 'Transaction'
          ) en ON TRUE
          WHERE a.id = ANY(array[:account_ids]::uuid[])
          GROUP BY dc.date, dc.category_name
        ),
        with_ma AS (
          SELECT date,
                category_name,
                current,
                TRUNC(AVG(current) OVER(ORDER BY date ROWS BETWEEN 12 PRECEDING AND CURRENT ROW), 2) moving_average
          FROM aggregated
        ),
        latest_12 AS (
          SELECT *
          FROM with_ma
          WHERE date >= :start_date::date - (:interval::interval * 11)
            AND date < :end_date::date
          ORDER BY date DESC
          LIMIT 12
        )
        SELECT *
        FROM latest_12
        ORDER BY date
      SQL
    end
end
