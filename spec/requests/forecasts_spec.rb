require "rails_helper"

RSpec.describe "Forecasts", type: :request do
  let(:address) { "Avenida Paulista 1578, Sao Paulo" }
  let(:unavailable_message) { "The weather service is unavailable. Please try again later." }

  before do
    stub_nominatim(address)
    stub_open_meteo
  end

  describe "HTML" do
    it "renders the search form" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Address", "Search")
      expect(response.body).not_to include('role="alert"')
    end

    it "shows the forecast for an address" do
      get root_path, params: { address: address }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
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

    it "serves the same page at /forecasts" do
      get forecasts_path, params: { address: address }, headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<form", "24.9°C")
    end

    it "shows the cached indicator when the forecast comes from the cache" do
      travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { get root_path, params: { address: address } }

      travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { get root_path, params: { address: address } }

      expect(response.body).to include("Cached result, fetched 12 minutes ago")
      expect(a_request(:get, HttpStubs::OPEN_METEO_URL).with(query: hash_including({}))).to have_been_made.once
      expect(a_request(:get, HttpStubs::NOMINATIM_URL).with(query: hash_including({}))).to have_been_made.once
    end

    it "hides the zip code when the location has none" do
      stub_nominatim("Sahara", results: [ nominatim_result("display_name" => "Sahara", "address" => { "country_code" => "dz" }) ])

      get root_path, params: { address: "Sahara" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sahara", "24.9°C")
      expect(response.body).not_to include("Zip code")
    end

    it "shows an error for a blank address" do
      get root_path, params: { address: "  " }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("Please enter an address.", "<form")
    end

    it "shows an error when the address is not found" do
      stub_nominatim("Nowhere", results: [])

      get root_path, params: { address: "Nowhere" }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("We could not find that address.", 'value="Nowhere"')
    end

    it "shows an error when the weather service is unavailable" do
      stub_request(:get, HttpStubs::OPEN_METEO_URL).with(query: hash_including({})).to_timeout

      get root_path, params: { address: address }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include(unavailable_message)
    end
  end

  describe "JSON" do
    def parsed_body = response.parsed_body

    it "returns the forecast for an address" do
      freeze_time do
        get forecasts_path(format: :json), params: { address: address }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        expect(parsed_body).to eq(
          "location" => {
            "latitude" => -23.56,
            "longitude" => -46.66,
            "zip_code" => "01311-200",
            "country_code" => "br",
            "display_name" => "Avenida Paulista, 1578, Sao Paulo, 01311-200, Brasil"
          },
          "forecast" => {
            "current_temperature" => 24.9,
            "current_condition" => "Drizzle",
            "today_high" => 26.0,
            "today_low" => 17.0,
            "upcoming_days" => [
              { "date" => "2026-10-25", "high" => 23.0, "low" => 15.7, "condition" => "Thunderstorm" }
            ]
          },
          "fetched_at" => Time.current.as_json,
          "cached" => false
        )
      end
    end

    it "negotiates JSON from the Accept header" do
      get forecasts_path, params: { address: address }, headers: { "Accept" => "application/json" }

      expect(response.media_type).to eq("application/json")
      expect(parsed_body["cached"]).to be(false)
    end

    it "reports a cached forecast with its original fetch time" do
      travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { get forecasts_path(format: :json), params: { address: address } }

      travel_to(Time.zone.local(2026, 10, 24, 12, 12)) { get forecasts_path(format: :json), params: { address: address } }

      expect(parsed_body).to include("cached" => true, "fetched_at" => "2026-10-24T12:00:00.000Z")
    end

    it "returns 400 when the address is missing" do
      get forecasts_path(format: :json)

      expect(response).to have_http_status(:bad_request)
      expect(parsed_body).to eq("error" => "Please enter an address.")
    end

    it "returns 400 when the address is blank" do
      get forecasts_path(format: :json), params: { address: " " }

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when the address is not a string" do
      get forecasts_path(format: :json), params: { address: [ "a", "b" ] }

      expect(response).to have_http_status(:bad_request)
      expect(parsed_body).to eq("error" => "Please enter an address.")
    end

    it "returns 404 when the address is not found" do
      stub_nominatim("Nowhere", results: [])

      get forecasts_path(format: :json), params: { address: "Nowhere" }

      expect(response).to have_http_status(:not_found)
      expect(parsed_body).to eq("error" => "We could not find that address.")
    end

    it "returns 503 when the geocoding service fails" do
      stub_nominatim(address, results: [], status: 429)

      get forecasts_path(format: :json), params: { address: address }

      expect(response).to have_http_status(:service_unavailable)
      expect(parsed_body).to eq("error" => "The address lookup service is unavailable. Please try again later.")
    end

    it "returns 503 without internal details when the weather service fails" do
      stub_open_meteo(body: { "current" => {} })

      get forecasts_path(format: :json), params: { address: address }

      expect(response).to have_http_status(:service_unavailable)
      expect(parsed_body).to eq("error" => unavailable_message)
    end
  end
end
