require "rails_helper"

RSpec.describe "Forecasts", type: :request do
  let(:address) { "Avenida Paulista 1578, Sao Paulo" }
  let(:location) do
    AddressGeocoder::Location.new(
      latitude: -23.56,
      longitude: -46.66,
      zip_code: "01311-200",
      country_code: "br",
      display_name: "Avenida Paulista, 1578, Sao Paulo, 01311-200, Brasil"
    )
  end
  let(:forecast) do
    WeatherForecaster::Forecast.new(
      current_temperature: 24.9,
      current_condition: "Drizzle",
      today_high: 26.0,
      today_low: 17.0,
      upcoming_days: [
        WeatherForecaster::DailyForecast.new(date: Date.new(2026, 10, 25), high: 23.0, low: 15.7, condition: "Thunderstorm")
      ]
    )
  end

  before do
    allow(AddressGeocoder).to receive(:call).with(address).and_return(location)
    allow(WeatherForecaster).to receive(:call).and_return(forecast)
  end

  it "renders the search form" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Address", "Search")
    expect(response.body).not_to include('role="alert"')
  end

  it "shows the forecast for an address" do
    get root_path, params: { address: address }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Avenida Paulista, 1578, Sao Paulo, 01311-200, Brasil",
      "Zip code: 01311-200",
      "24.9°C",
      "Drizzle",
      "High 26.0°C",
      "Low 17.0°C",
      "Sun, Oct 25",
      "Thunderstorm"
    )
    expect(response.body).not_to include("Cached result")
  end

  it "shows the cached indicator when the forecast comes from the cache" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { get root_path, params: { address: address } }

    travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { get root_path, params: { address: address } }

    expect(response.body).to include("Cached result, fetched 12 minutes ago")
    expect(WeatherForecaster).to have_received(:call).once
  end

  it "shows an error for a blank address" do
    get root_path, params: { address: "  " }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please enter an address.", "<form")
  end

  it "shows an error when the address is not found" do
    allow(AddressGeocoder).to receive(:call).with("Nowhere").and_raise(AddressGeocoder::AddressNotFound, "We could not find that address.")

    get root_path, params: { address: "Nowhere" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("We could not find that address.", 'value="Nowhere"')
  end

  it "shows an error when the weather service is unavailable" do
    allow(WeatherForecaster).to receive(:call).and_raise(WeatherForecaster::Error, "The weather service is unavailable. Please try again later.")

    get root_path, params: { address: address }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("The weather service is unavailable. Please try again later.")
  end
end
