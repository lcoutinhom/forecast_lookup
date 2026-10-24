require "rails_helper"

RSpec.describe ForecastSearch do
  let(:address) { "Avenida Paulista 1578, Sao Paulo" }
  let(:neighbor_address) { "MASP, Sao Paulo" }
  let(:forecast) { build_forecast }

  before do
    allow(AddressGeocoder).to receive(:call).with(address).and_return(build_location)
    allow(AddressGeocoder).to receive(:call).with(neighbor_address).and_return(build_location(display_name: "MASP", zip_code: "01311200"))
    allow(WeatherForecaster).to receive(:call).and_return(forecast)
  end

  it "fetches the forecast when nothing is cached" do
    freeze_time do
      result = described_class.call(address)

      expect(result).to have_attributes(location: build_location, forecast: forecast, cached: false, fetched_at: Time.current)
      expect(WeatherForecaster).to have_received(:call).with(latitude: -23.56, longitude: -46.66).once
    end
  end

  it "returns the cached forecast with the original fetch time on the next call" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(address) }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { described_class.call(address) }

    expect(result).to have_attributes(forecast: forecast, cached: true, fetched_at: Time.zone.local(2026, 10, 24, 12, 0))
    expect(WeatherForecaster).to have_received(:call).once
  end

  it "shares the cache between addresses in the same zip code" do
    described_class.call(address)
    result = described_class.call(neighbor_address)

    expect(result).to have_attributes(cached: true, location: have_attributes(display_name: "MASP"))
    expect(WeatherForecaster).to have_received(:call).once
  end

  it "does not share the cache between countries with the same zip code" do
    allow(AddressGeocoder).to receive(:call).with("Elsewhere").and_return(build_location(country_code: "pt"))

    described_class.call(address)
    result = described_class.call("Elsewhere")

    expect(result.cached).to be(false)
    expect(WeatherForecaster).to have_received(:call).twice
  end

  it "keeps the cache for 30 minutes" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(address) }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 29)) { described_class.call(address) }

    expect(result.cached).to be(true)
  end

  it "fetches again after the cache expires" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(address) }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 31)) { described_class.call(address) }

    expect(result).to have_attributes(cached: false, fetched_at: Time.zone.local(2026, 10, 24, 12, 31))
    expect(WeatherForecaster).to have_received(:call).twice
  end

  it "builds the cache key from the normalized zip code and country code" do
    location = build_location(zip_code: " sw1a 1aa ", country_code: "GB")

    expect(described_class.cache_key_for(location)).to eq("forecast/gb/SW1A1AA")
  end
end
