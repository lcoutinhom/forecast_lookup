require "rails_helper"

RSpec.describe AddressGeocoder do
  let(:address) { "1600 Amphitheatre Parkway, Mountain View, CA" }
  let(:search_url) { "https://nominatim.openstreetmap.org/search" }
  let(:search_query) { { q: address, format: "json", addressdetails: "1", limit: "1" } }

  def stub_search(body:, status: 200)
    stub_request(:get, search_url)
      .with(query: search_query, headers: { "User-Agent" => AddressGeocoder::USER_AGENT })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def search_result(postcode: "94043")
    {
      "lat" => "37.4224857",
      "lon" => "-122.0855846",
      "display_name" => "Google Building 41, 1600, Amphitheatre Parkway, Mountain View, California, 94043, United States",
      "address" => { "postcode" => postcode, "country_code" => "us" }.compact
    }
  end

  it "returns the location of the address" do
    stub_search(body: [ search_result ])

    location = described_class.call(address)

    expect(location).to have_attributes(
      latitude: 37.4224857,
      longitude: -122.0855846,
      zip_code: "94043",
      country_code: "us",
      display_name: a_string_starting_with("Google Building 41")
    )
  end

  it "raises AddressNotFound when there are no results" do
    stub_search(body: [])

    expect { described_class.call(address) }
      .to raise_error(AddressGeocoder::AddressNotFound, "We could not find that address.")
  end

  it "raises AddressNotFound when the result has no postcode" do
    stub_search(body: [ search_result(postcode: nil) ])

    expect { described_class.call(address) }
      .to raise_error(AddressGeocoder::AddressNotFound, /no zip code/)
  end

  it "raises ServiceUnavailable on timeout" do
    stub_request(:get, search_url).with(query: search_query).to_timeout

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::ServiceUnavailable)
  end

  it "raises ServiceUnavailable when the connection fails" do
    stub_request(:get, search_url).with(query: search_query).to_raise(SocketError)

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::ServiceUnavailable)
  end

  it "raises ServiceUnavailable on a non-success response" do
    stub_search(body: { error: "Too many requests" }, status: 429)

    expect { described_class.call(address) }.to raise_error(AddressGeocoder::ServiceUnavailable)
  end
end
