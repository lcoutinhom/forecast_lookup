# Forecast Lookup

Type an address and get the current weather, today's high and low, and a 5-day forecast for it.
Forecasts are cached per zip code for 30 minutes, and the page shows when a result came from the cache.

## Running

Ruby version is in `.ruby-version`. No API keys or environment variables are needed.

```
bundle install
bin/rails server
bundle exec rspec
```

The app runs at http://localhost:3000.

## Decisions

- Nominatim (OpenStreetMap) for geocoding and Open-Meteo for weather. Neither needs an API key, so the app works right after cloning. Both are called with `Net::HTTP`, and results are plain `Data.define` objects.
- The flow lives in three small classes in `app/services`: `AddressGeocoder`, `WeatherForecaster` and `ForecastSearch`, which ties them together and handles caching. It is not called `ForecastLookup` because that name is taken by the application module.
- The cache key is the normalized zip code plus the country code (`forecast/br/01311200`), because zip codes repeat across countries. Different addresses in the same zip code share the entry, and the entry stores the original fetch time for the "Cached result, fetched 12 minutes ago" notice.
- `memory_store` in every environment, so caching works in development without `rails dev:cache`. It lives inside one process and is lost on restart. In production I would switch to Redis or Solid Cache, so every Puma worker and host shares the same entries.
- Upstream failures become friendly messages above the form: 422 for a blank or unknown address, 503 when an API is down. The test suite stubs all HTTP with WebMock.

## With more time

- Cache geocoding results too. Every search currently calls Nominatim, which allows about one request per second.
- Serve the stale forecast when Open-Meteo is down, and add retries with backoff.
- Let the user choose between Celsius and Fahrenheit.
- Add a system test for the full page flow and a CI workflow running RSpec and RuboCop.
