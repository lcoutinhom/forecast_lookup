module ForecastsHelper
  def temperature(value)
    "#{number_with_precision(value, precision: 1)}°C"
  end

  def forecast_day(date)
    date.strftime("%a, %b %-d")
  end

  def cached_notice(fetched_at)
    "Cached result, fetched #{time_ago_in_words(fetched_at)} ago"
  end
end
