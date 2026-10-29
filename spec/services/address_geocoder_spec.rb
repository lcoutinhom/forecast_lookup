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

  it "returns a location without a zip code when the result has no postcode" do
    search_result["address"].delete("postcode")
    stub_search(body: [ search_result ])

    expect(described_class.call(address)).to have_attributes(latitude: -23.5616836, longitude: -46.6565685, zip_code: nil)
  end

  it "treats a blank postcode as no zip code" do
    search_result["address"]["postcode"] = " "
    stub_search(body: [ search_result ])

    expect(described_class.call(address).zip_code).to be_nil
  end

  it "returns a location when the result has no address details" do
    search_result.delete("address")
    stub_search(body: [ search_result ])

    expect(described_class.call(address)).to have_attributes(zip_code: nil, country_code: nil)
  end

  [
    [ "missing", nil ],
    [ "not a number", "north" ],
    [ "out of range", "91.5" ],
    [ "not finite", "NaN" ]
  ].each do |description, latitude|
    it "raises AddressNotFound when the latitude is #{description}" do
      stub_search(body: [ search_result.merge("lat" => latitude) ])

      expect { described_class.call(address) }
        .to raise_error(AddressGeocoder::AddressNotFound, "We could not find that address.")
    end
  end

  it "raises AddressNotFound when the longitude is out of range" do
    stub_search(body: [ search_result.merge("lon" => "-180.01") ])

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::AddressNotFound)
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
