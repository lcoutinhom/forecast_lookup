module ForecastFixtures
  def build_location(**attributes)
    AddressGeocoder::Location.new(
      latitude: -23.56,
      longitude: -46.66,
      zip_code: "01311-200",
      country_code: "br",
      display_name: "Avenida Paulista, 1578, Sao Paulo, 01311-200, Brasil",
      **attributes
    )
  end

  def build_forecast(**attributes)
    WeatherForecaster::Forecast.new(
      current_temperature: 24.9,
      current_condition: "Drizzle",
      today_high: 26.0,
      today_low: 17.0,
      upcoming_days: [
        WeatherForecaster::DailyForecast.new(date: Date.new(2026, 10, 25), high: 23.0, low: 15.7, condition: "Thunderstorm")
      ],
      **attributes
    )
  end
end
