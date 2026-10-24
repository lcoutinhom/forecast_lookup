require "rails_helper"

RSpec.describe ForecastSearch do
  let(:paulista) { "Avenida Paulista 1578, Sao Paulo" }
  let(:masp) { "MASP, Sao Paulo" }
  let(:forecast) do
    WeatherForecaster::Forecast.new(
      current_temperature: 24.9,
      current_condition: "Drizzle",
      today_high: 24.9,
      today_low: 17.0,
      upcoming_days: []
    )
  end

  def location(display_name:, zip_code: "01311-200", country_code: "br")
    AddressGeocoder::Location.new(
      latitude: -23.56,
      longitude: -46.66,
      zip_code: zip_code,
      country_code: country_code,
      display_name: display_name
    )
  end

  before do
    allow(AddressGeocoder).to receive(:call).with(paulista).and_return(location(display_name: "Avenida Paulista, 1578"))
    allow(AddressGeocoder).to receive(:call).with(masp).and_return(location(display_name: "MASP", zip_code: "01311200"))
    allow(WeatherForecaster).to receive(:call).and_return(forecast)
  end

  it "fetches the forecast when nothing is cached" do
    freeze_time do
      result = described_class.call(paulista)

      expect(result).to have_attributes(forecast: forecast, cached: false, fetched_at: Time.current)
      expect(result.location.display_name).to eq("Avenida Paulista, 1578")
      expect(WeatherForecaster).to have_received(:call).with(latitude: -23.56, longitude: -46.66).once
    end
  end

  it "returns the cached forecast with the original fetch time on the next call" do
    first_fetched_at = travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(paulista).fetched_at }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { described_class.call(paulista) }

    expect(result).to have_attributes(forecast: forecast, cached: true, fetched_at: first_fetched_at)
    expect(WeatherForecaster).to have_received(:call).once
  end

  it "shares the cache between addresses in the same zip code" do
    described_class.call(paulista)
    result = described_class.call(masp)

    expect(result.cached).to be(true)
    expect(result.location.display_name).to eq("MASP")
    expect(WeatherForecaster).to have_received(:call).once
  end

  it "does not share the cache between countries with the same zip code" do
    allow(AddressGeocoder).to receive(:call).with("Elsewhere").and_return(location(display_name: "Elsewhere", country_code: "pt"))

    described_class.call(paulista)
    result = described_class.call("Elsewhere")

    expect(result.cached).to be(false)
    expect(WeatherForecaster).to have_received(:call).twice
  end

  it "keeps the cache for 30 minutes" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(paulista) }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 29)) { described_class.call(paulista) }

    expect(result.cached).to be(true)
  end

  it "fetches again after the cache expires" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { described_class.call(paulista) }

    result = travel_to(Time.zone.local(2026, 10, 24, 12, 31)) { described_class.call(paulista) }

    expect(result).to have_attributes(cached: false, fetched_at: Time.zone.local(2026, 10, 24, 12, 31))
    expect(WeatherForecaster).to have_received(:call).twice
  end

  it "builds the cache key from the normalized zip code and country code" do
    key = described_class.cache_key_for(location(display_name: "London", zip_code: " sw1a 1aa ", country_code: "GB"))

    expect(key).to eq("forecast/gb/SW1A1AA")
  end
end
