module HttpStubs
  NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
  OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

  def nominatim_result(**attributes)
    {
      "lat" => "-23.56",
      "lon" => "-46.66",
      "display_name" => "Avenida Paulista, 1578, Sao Paulo, 01311-200, Brasil",
      "address" => { "postcode" => "01311-200", "country_code" => "br" }
    }.merge(attributes.stringify_keys)
  end

  def open_meteo_body
    {
      "current" => { "temperature_2m" => 24.9, "weather_code" => 51 },
      "daily" => {
        "time" => %w[2026-10-24 2026-10-25],
        "weather_code" => [ 51, 95 ],
        "temperature_2m_max" => [ 26.0, 23.0 ],
        "temperature_2m_min" => [ 17.0, 15.7 ]
      }
    }
  end

  def stub_nominatim(address, results: [ nominatim_result ], status: 200)
    stub_request(:get, NOMINATIM_URL)
      .with(query: hash_including(q: address))
      .to_return(status: status, body: results.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_open_meteo(body: open_meteo_body, status: 200)
    stub_request(:get, OPEN_METEO_URL)
      .with(query: hash_including({}))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end
