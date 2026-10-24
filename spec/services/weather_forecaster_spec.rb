require "rails_helper"

RSpec.describe WeatherForecaster do
  let(:forecast_url) { "https://api.open-meteo.com/v1/forecast" }
  let(:forecast_query) do
    {
      latitude: "-23.56",
      longitude: "-46.66",
      current: "temperature_2m,weather_code",
      daily: "weather_code,temperature_2m_max,temperature_2m_min",
      temperature_unit: "celsius",
      timezone: "auto",
      forecast_days: "6"
    }
  end
  let(:forecast_body) do
    {
      "current" => { "temperature_2m" => 24.9, "weather_code" => 51 },
      "daily" => {
        "time" => %w[2026-10-24 2026-10-25 2026-10-26 2026-10-27 2026-10-28 2026-10-29],
        "weather_code" => [ 51, 96, 0, 3, 45, 999 ],
        "temperature_2m_max" => [ 24.9, 23.0, 19.6, 19.6, 22.8, 20.4 ],
        "temperature_2m_min" => [ 17.0, 15.7, 13.0, 12.3, 13.7, 16.0 ]
      }
    }
  end

  def stub_forecast(body:, status: 200)
    stub_request(:get, forecast_url)
      .with(query: forecast_query)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def call_forecaster
    described_class.call(latitude: -23.56, longitude: -46.66)
  end

  it "returns the current weather and today's range" do
    stub_forecast(body: forecast_body.to_json)

    expect(call_forecaster).to have_attributes(
      current_temperature: 24.9,
      current_condition: "Drizzle",
      today_high: 24.9,
      today_low: 17.0
    )
  end

  it "returns the next five days" do
    stub_forecast(body: forecast_body.to_json)

    upcoming_days = call_forecaster.upcoming_days

    expect(upcoming_days.map(&:date)).to eq((Date.new(2026, 10, 25)..Date.new(2026, 10, 29)).to_a)
    expect(upcoming_days.map(&:condition)).to eq([ "Thunderstorm with hail", "Clear sky", "Overcast", "Fog", "Unknown" ])
    expect(upcoming_days.first).to have_attributes(high: 23.0, low: 15.7)
  end

  it "raises Error on a non-success response" do
    stub_forecast(body: { error: true, reason: "Invalid latitude" }.to_json, status: 400)

    expect { call_forecaster }.to raise_error(WeatherForecaster::Error)
  end

  it "raises Error on timeout" do
    stub_request(:get, forecast_url).with(query: forecast_query).to_timeout

    expect { call_forecaster }.to raise_error(WeatherForecaster::Error)
  end

  it "raises Error when the connection fails" do
    stub_request(:get, forecast_url).with(query: forecast_query).to_raise(Errno::ECONNREFUSED)

    expect { call_forecaster }.to raise_error(WeatherForecaster::Error)
  end

  it "raises Error when the body is not JSON" do
    stub_forecast(body: "<html>Bad gateway</html>")

    expect { call_forecaster }.to raise_error(WeatherForecaster::Error)
  end

  it "raises Error when expected fields are missing" do
    stub_forecast(body: { "current" => {} }.to_json)

    expect { call_forecaster }.to raise_error(WeatherForecaster::Error)
  end
end
