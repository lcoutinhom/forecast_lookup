class ForecastSearch
  CACHE_TTL = 30.minutes

  Result = Data.define(:location, :forecast, :fetched_at, :cached)

  def self.call(address, **dependencies)
    new(address, **dependencies).call
  end

  def self.cache_key_for(location)
    zip_code = location.zip_code.to_s.upcase.gsub(/[^0-9A-Z]/, "")
    country_code = location.country_code.to_s.downcase
    "forecast/#{country_code}/#{zip_code}"
  end

  def initialize(address, geocoder: AddressGeocoder, forecaster: WeatherForecaster, cache: Rails.cache)
    @address = address
    @geocoder = geocoder
    @forecaster = forecaster
    @cache = cache
  end

  def call
    location = @geocoder.call(@address)
    cached = true
    entry = @cache.fetch(self.class.cache_key_for(location), expires_in: CACHE_TTL) do
      cached = false
      fetch_forecast(location)
    end

    Result.new(location: location, forecast: entry[:forecast], fetched_at: entry[:fetched_at], cached: cached)
  end

  private

  def fetch_forecast(location)
    forecast = @forecaster.call(latitude: location.latitude, longitude: location.longitude)
    { forecast: forecast, fetched_at: Time.current }
  end
end
