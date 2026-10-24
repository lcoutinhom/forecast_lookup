require "net/http"

class WeatherForecaster
  class Error < StandardError; end

  Forecast = Data.define(:current_temperature, :current_condition, :today_high, :today_low, :upcoming_days)
  DailyForecast = Data.define(:date, :high, :low, :condition)

  ENDPOINT = URI("https://api.open-meteo.com/v1/forecast")
  TIMEOUT_SECONDS = 5
  UPCOMING_DAYS = 5
  NETWORK_ERRORS = [ Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError ].freeze
  INVALID_RESPONSE_ERRORS = [ JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError ].freeze

  CONDITIONS = {
    [ 0 ] => "Clear sky",
    [ 1 ] => "Mainly clear",
    [ 2 ] => "Partly cloudy",
    [ 3 ] => "Overcast",
    [ 45, 48 ] => "Fog",
    [ 51, 53, 55 ] => "Drizzle",
    [ 56, 57 ] => "Freezing drizzle",
    [ 61, 63, 65 ] => "Rain",
    [ 66, 67 ] => "Freezing rain",
    [ 71, 73, 75 ] => "Snow",
    [ 77 ] => "Snow grains",
    [ 80, 81, 82 ] => "Rain showers",
    [ 85, 86 ] => "Snow showers",
    [ 95 ] => "Thunderstorm",
    [ 96, 99 ] => "Thunderstorm with hail"
  }.flat_map { |codes, condition| codes.map { |code| [ code, condition ] } }.to_h.freeze

  def self.call(latitude:, longitude:)
    new(latitude:, longitude:).call
  end

  def self.condition_for(weather_code)
    CONDITIONS.fetch(weather_code, "Unknown")
  end

  def initialize(latitude:, longitude:)
    @latitude = latitude
    @longitude = longitude
  end

  def call
    build_forecast(fetch_data)
  rescue *NETWORK_ERRORS, *INVALID_RESPONSE_ERRORS
    raise Error, "The weather service is unavailable. Please try again later."
  end

  private

  def fetch_data
    response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.get(forecast_uri.request_uri)
    end
    raise Error, "The weather service returned an unexpected response." unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def forecast_uri
    ENDPOINT.dup.tap do |uri|
      uri.query = URI.encode_www_form(
        latitude: @latitude,
        longitude: @longitude,
        current: "temperature_2m,weather_code",
        daily: "weather_code,temperature_2m_max,temperature_2m_min",
        temperature_unit: "celsius",
        timezone: "auto",
        forecast_days: UPCOMING_DAYS + 1
      )
    end
  end

  def build_forecast(data)
    current = data.fetch("current")
    today, *upcoming_days = daily_forecasts(data.fetch("daily"))

    Forecast.new(
      current_temperature: Float(current.fetch("temperature_2m")),
      current_condition: self.class.condition_for(current.fetch("weather_code")),
      today_high: today.high,
      today_low: today.low,
      upcoming_days: upcoming_days
    )
  end

  def daily_forecasts(daily)
    daily.fetch("time").each_index.map do |index|
      DailyForecast.new(
        date: Date.iso8601(daily.fetch("time")[index]),
        high: Float(daily.fetch("temperature_2m_max")[index]),
        low: Float(daily.fetch("temperature_2m_min")[index]),
        condition: self.class.condition_for(daily.fetch("weather_code")[index])
      )
    end
  end
end
