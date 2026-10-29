# Forecast Lookup

Type an address and get the current weather, today's high and low, and a 5-day forecast for it, as an HTML page or as JSON.
Forecasts are cached for 30 minutes, and both formats say when a result came from the cache.

## Running

### Locally

Ruby version is in `.ruby-version`. No API keys or environment variables are needed.

```
bundle install
bin/rails server
bundle exec rspec
bin/rubocop
```

The app runs at http://localhost:3000. Development and test cache in memory, so no database setup is needed.

### Docker

```
docker compose up --build
```

The app runs in production mode at http://localhost:3000. On start, `bin/docker-entrypoint` runs `bin/rails db:prepare`, which creates the SQLite cache database from `db/cache_schema.rb`; it lives in the `storage` volume, so cached entries survive restarts.

- `SECRET_KEY_BASE` is read from your shell. If it is unset, the entrypoint generates a temporary one, which is fine because the app keeps no sessions or signed data. Set it in any real deployment.
- `RAILS_SSL=false` in `compose.yaml` serves plain HTTP on localhost. Without it, production forces HTTPS, as it would behind a TLS-terminating proxy.

Run the test suite in a container built from the same Dockerfile, with the development and test gems:

```
docker compose run --rm test
```

## API

`GET /forecasts.json?address=...`, or `GET /forecasts` with `Accept: application/json`. The HTML page is served at `/` and `/forecasts`.

```
curl "http://localhost:3000/forecasts.json?address=Times%20Square,%20New%20York"
```

```json
{
  "location": {
    "latitude": 40.7570095,
    "longitude": -73.9859724,
    "zip_code": "10036",
    "country_code": "us",
    "display_name": "Times Square, Manhattan, New York County, New York, 10036, United States"
  },
  "forecast": {
    "current_temperature": 18.1,
    "current_condition": "Clear sky",
    "today_high": 19.5,
    "today_low": 7.4,
    "upcoming_days": [
      { "date": "2026-10-30", "high": 18.3, "low": 6.3, "condition": "Overcast" }
    ]
  },
  "fetched_at": "2026-10-29T21:30:05.737Z",
  "cached": false
}
```

Temperatures are in Celsius, `upcoming_days` has five entries (shortened above), and `zip_code` is `null` for places without one. `fetched_at` is when the forecast was fetched from Open-Meteo, so it is older than the request when `cached` is `true`.

Errors have the same status in both formats. JSON errors carry only the user-facing message:

```json
{ "error": "We could not find that address." }
```

| Status | When |
| --- | --- |
| 200 | Forecast found |
| 400 | `address` is missing, blank or not a string |
| 404 | Nominatim has no result with valid coordinates for the address |
| 503 | Nominatim or Open-Meteo timed out, refused the connection, rate limited us or returned an error or an unreadable response |

## Architecture

Three small classes in `app/services`, returning plain `Data.define` objects:

- `AddressGeocoder` calls Nominatim (OpenStreetMap) and returns a `Location`. Latitude and longitude are required and checked to be finite and in range; the zip code is optional.
- `WeatherForecaster` calls Open-Meteo and returns a `Forecast` with the current weather, today's range and the next five days.
- `ForecastSearch` ties them together and owns both caches. Its geocoder, forecaster and cache are constructor arguments that default to `AddressGeocoder`, `WeatherForecaster` and `Rails.cache`, so its specs pass verifying doubles and a private `MemoryStore` instead of stubbing classes. It is not called `ForecastLookup` because that name is taken by the application module.

`ForecastsController#show` calls `ForecastSearch` once and renders the result as HTML or JSON with `respond_to`. The domain errors (`AddressGeocoder::AddressNotFound`, `AddressGeocoder::ServiceUnavailable` and `WeatherForecaster::Error`) are mapped to statuses with `rescue_from`. Their messages are written for users, and nothing else reaches the response.

Neither API needs a key, so the app works right after cloning. The test suite stubs all HTTP with WebMock and controls time with `travel_to`.

## Caching

| Cache | Key | TTL |
| --- | --- | --- |
| Geocoding | `geocode/<SHA-256 of the address, lowercased and with whitespace collapsed>` | 24 hours |
| Forecast | `forecast/<country>/<zip>`, e.g. `forecast/br/01311200` | 30 minutes |
| Forecast, no zip code | `forecast/coords/<lat>_<lon>` rounded to 2 decimals, e.g. `forecast/coords/27.99_86.93` | 30 minutes |

- Zip codes are uppercased and stripped to letters and digits (` sw1a 1aa ` becomes `SW1A1AA`), and the country is part of the key because zip codes repeat across countries. Different addresses in the same zip code share a forecast.
- Locations without a zip code, or without a country code, fall back to coordinates. Two decimals is about 1 km, finer than Open-Meteo's grid. Two points a few meters apart on either side of a rounding boundary get different keys; that costs an extra request, never a wrong forecast.
- Failed lookups raise inside `Rails.cache.fetch`, so errors are never cached.
- `cached` in the result is about the forecast only. A cached location with a freshly fetched forecast reports `cached: false`.
- Production uses Solid Cache on SQLite (`config/cache.yml`, `config/database.yml`), so every Puma worker and restart shares the same entries. Development and test use `memory_store`.

## Trade-offs

- **Dependency injection** keeps `ForecastSearch` testable through its constructor, without stubbing `AddressGeocoder` or `WeatherForecaster` globally. It uses plain keyword arguments with defaults, no container.
- **Two caches** because the inputs change at different rates. Where an address is changes almost never, so it is cached for a day. The weather changes within the hour. Many addresses also share one forecast entry.
- **Optional zip codes** because Nominatim returns valid places without one (landmarks, rural areas, some countries). Rejecting them would turn good coordinates into "address not found".
- **Solid Cache** is the Rails 8 default and needs no extra service: a SQLite file shared by the workers on one host. It adds Active Record and Active Job (Solid Cache's expiry job class must load), though the app has no models. Running several hosts would mean pointing the `cache` database at PostgreSQL or MySQL, or switching to Redis.
- **One service for HTML and JSON**, so both formats get the same validation, caching and error mapping. Only the rendering differs.
- **No 502.** Both providers' failures already surface as one "unavailable, try again later" error, and a client would react the same to 502 and 503. Splitting them would mean new exception classes in both services for no change in client behavior.
- **Nominatim rate limits.** The usage policy allows about one request per second. The geocoding cache cuts repeated lookups, but nothing enforces the limit across Puma threads or workers. A per-process throttle would block request threads and still not hold across processes, so I left it out. When Nominatim answers 429, the user sees a 503. Production traffic would need a shared limiter or a self-hosted or commercial geocoder.

## With more time

- Serve the stale forecast when Open-Meteo is down, and add retries with backoff.
- Let the user choose between Celsius and Fahrenheit.
- Add a system test for the full page flow and a CI workflow running RSpec and RuboCop.
