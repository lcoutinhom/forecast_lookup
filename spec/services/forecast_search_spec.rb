require "rails_helper"

RSpec.describe ForecastSearch do
  let(:address) { "Avenida Paulista 1578, Sao Paulo" }
  let(:neighbor_address) { "MASP, Sao Paulo" }
  let(:location) { build_location }
  let(:forecast) { build_forecast }
  let(:geocoder) { class_double(AddressGeocoder) }
  let(:forecaster) { class_double(WeatherForecaster, call: forecast) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(geocoder).to receive(:call).with(address).and_return(location)
    allow(geocoder).to receive(:call).with(neighbor_address).and_return(build_location(display_name: "MASP", zip_code: "01311200"))
  end

  def search(query = address)
    described_class.call(query, geocoder: geocoder, forecaster: forecaster, cache: cache)
  end

  it "fetches the forecast when nothing is cached" do
    freeze_time do
      result = search

      expect(result).to have_attributes(location: location, forecast: forecast, cached: false, fetched_at: Time.current)
      expect(geocoder).to have_received(:call).with(address).once
      expect(forecaster).to have_received(:call).with(latitude: -23.56, longitude: -46.66).once
    end
  end

  it "returns the cached forecast with the original fetch time on the next call" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { search }

    expect(result).to have_attributes(forecast: forecast, cached: true, fetched_at: Time.zone.local(2026, 10, 24, 12, 0))
    expect(forecaster).to have_received(:call).once
  end

  it "shares the cache between addresses in the same zip code" do
    search
    result = search(neighbor_address)

    expect(result).to have_attributes(cached: true, location: have_attributes(display_name: "MASP"))
    expect(forecaster).to have_received(:call).once
  end

  it "does not share the cache between countries with the same zip code" do
    allow(geocoder).to receive(:call).with("Elsewhere").and_return(build_location(country_code: "pt"))

    search
    result = search("Elsewhere")

    expect(result.cached).to be(false)
    expect(forecaster).to have_received(:call).twice
  end

  it "keeps the cache for 30 minutes" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 29)) { search }

    expect(result.cached).to be(true)
  end

  it "fetches again after the cache expires" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 31)) { search }

    expect(result).to have_attributes(cached: false, fetched_at: Time.zone.local(2026, 10, 24, 12, 31))
    expect(forecaster).to have_received(:call).twice
  end

  it "caches the forecast of a location without a zip code by its coordinates" do
    allow(geocoder).to receive(:call).with("Sahara").and_return(build_location(zip_code: nil, latitude: 23.4162, longitude: 25.6628))

    search("Sahara")

    expect(cache.exist?("forecast/coords/23.42_25.66")).to be(true)
  end

  it "propagates geocoding errors without fetching a forecast" do
    allow(geocoder).to receive(:call).with("Nowhere").and_raise(AddressGeocoder::AddressNotFound, "We could not find that address.")

    expect { search("Nowhere") }.to raise_error(AddressGeocoder::AddressNotFound, "We could not find that address.")
    expect(forecaster).not_to have_received(:call)
  end

  it "propagates forecast errors without caching them" do
    allow(forecaster).to receive(:call).and_raise(WeatherForecaster::Error, "The weather service is unavailable. Please try again later.")

    expect { search }.to raise_error(WeatherForecaster::Error)
    expect(cache.exist?(described_class.cache_key_for(location))).to be(false)
  end

  it "uses AddressGeocoder, WeatherForecaster and Rails.cache by default" do
    stub_nominatim(address)
    stub_open_meteo

    result = described_class.call(address)

    expect(result).to have_attributes(cached: false, location: have_attributes(zip_code: "01311-200"), forecast: have_attributes(current_temperature: 24.9))
    expect(Rails.cache.exist?(described_class.cache_key_for(result.location))).to be(true)
  end

  describe "geocoding cache" do
    it "geocodes an address only once while it is cached" do
      search
      search

      expect(geocoder).to have_received(:call).once
    end

    it "shares the entry between spellings that differ only in case and whitespace" do
      search
      search("  avenida paulista   1578, SAO PAULO ")

      expect(geocoder).to have_received(:call).once
    end

    it "geocodes different addresses separately" do
      search
      search(neighbor_address)

      expect(geocoder).to have_received(:call).twice
    end

    it "keeps the location for 24 hours" do
      travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }
      travel_to(Time.zone.local(2026, 10, 25, 11, 59)) { search }

      expect(geocoder).to have_received(:call).once
    end

    it "geocodes again after the entry expires" do
      travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }
      travel_to(Time.zone.local(2026, 10, 25, 12, 1)) { search }

      expect(geocoder).to have_received(:call).twice
    end

    it "does not cache failed lookups" do
      allow(geocoder).to receive(:call).with("Nowhere").and_raise(AddressGeocoder::ServiceUnavailable)

      2.times { expect { search("Nowhere") }.to raise_error(AddressGeocoder::ServiceUnavailable) }

      expect(geocoder).to have_received(:call).with("Nowhere").twice
      expect(cache.exist?(described_class.geocode_cache_key_for("Nowhere"))).to be(false)
    end

    it "reports a fresh forecast when only the location came from the cache" do
      travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { search }

      result = travel_to(Time.zone.local(2026, 10, 24, 12, 31)) { search }

      expect(result.cached).to be(false)
      expect(geocoder).to have_received(:call).once
      expect(forecaster).to have_received(:call).twice
    end
  end

  describe ".cache_key_for" do
    it "builds the key from the normalized zip code and country code" do
      location = build_location(zip_code: " sw1a 1aa ", country_code: "GB")

      expect(described_class.cache_key_for(location)).to eq("forecast/gb/SW1A1AA")
    end

    it "gives the same zip code in different countries different keys" do
      brazil = described_class.cache_key_for(build_location(zip_code: "1000", country_code: "br"))
      belgium = described_class.cache_key_for(build_location(zip_code: "1000", country_code: "be"))

      expect(brazil).not_to eq(belgium)
    end

    it "falls back to coordinates rounded to two decimals when there is no zip code" do
      location = build_location(zip_code: nil, latitude: 40.712776, longitude: -74.005974)

      expect(described_class.cache_key_for(location)).to eq("forecast/coords/40.71_-74.01")
    end

    it "falls back to coordinates when the zip code has no letters or digits" do
      location = build_location(zip_code: " - ", latitude: 1.0, longitude: 2.0)

      expect(described_class.cache_key_for(location)).to eq("forecast/coords/1.00_2.00")
    end

    it "falls back to coordinates when the country code is missing" do
      location = build_location(country_code: nil, latitude: 1.0, longitude: 2.0)

      expect(described_class.cache_key_for(location)).to eq("forecast/coords/1.00_2.00")
    end

    it "gives nearby coordinates the same key, including across the equator and Greenwich" do
      first = described_class.cache_key_for(build_location(zip_code: nil, latitude: 0.001, longitude: -0.001))
      second = described_class.cache_key_for(build_location(zip_code: nil, latitude: -0.001, longitude: 0.001))

      expect(first).to eq("forecast/coords/0.00_0.00")
      expect(second).to eq(first)
    end
  end

  describe ".geocode_cache_key_for" do
    it "hashes the normalized address with SHA-256" do
      expect(described_class.geocode_cache_key_for(" Main  St ")).to eq("geocode/#{Digest::SHA256.hexdigest("main st")}")
    end
  end
end
