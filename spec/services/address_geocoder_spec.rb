require "rails_helper"

RSpec.describe AddressGeocoder do
  let(:address) { "Avenida Paulista 1578, Sao Paulo" }
  let(:search_url) { "https://nominatim.openstreetmap.org/search" }
  let(:search_query) { { q: address, format: "json", addressdetails: "1", limit: "1" } }
  let(:search_result) do
    {
      "lat" => "-23.5616836",
      "lon" => "-46.6565685",
      "display_name" => "Avenida Paulista, 1578, Bela Vista, Sao Paulo, 01311-200, Brasil",
      "address" => { "postcode" => "01311-200", "country_code" => "br" }
    }
  end

  def stub_search(body:, status: 200)
    stub_request(:get, search_url)
      .with(query: search_query, headers: { "User-Agent" => AddressGeocoder::USER_AGENT })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "returns the location of the address" do
    stub_search(body: [ search_result ])

    expect(described_class.call(address)).to have_attributes(
      latitude: -23.5616836,
      longitude: -46.6565685,
      zip_code: "01311-200",
      country_code: "br",
      display_name: "Avenida Paulista, 1578, Bela Vista, Sao Paulo, 01311-200, Brasil"
    )
  end

  it "raises AddressNotFound when there are no results" do
    stub_search(body: [])

    expect { described_class.call(address) }
      .to raise_error(AddressGeocoder::AddressNotFound, "We could not find that address.")
  end

  it "raises AddressNotFound when the result has no postcode" do
    search_result["address"].delete("postcode")
    stub_search(body: [ search_result ])

    expect { described_class.call(address) }
      .to raise_error(AddressGeocoder::AddressNotFound, "That address has no zip code. Try a more specific address.")
  end

  it "raises ServiceUnavailable on a non-success response" do
    stub_search(body: { error: "Too many requests" }, status: 429)

    expect { described_class.call(address) }
      .to raise_error(AddressGeocoder::ServiceUnavailable, "The address lookup service is unavailable. Please try again later.")
  end

  it "raises ServiceUnavailable on timeout" do
    stub_request(:get, search_url).with(query: search_query).to_timeout

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::ServiceUnavailable)
  end

  it "raises ServiceUnavailable when the connection fails" do
    stub_request(:get, search_url).with(query: search_query).to_raise(SocketError)

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::ServiceUnavailable)
  end
end
