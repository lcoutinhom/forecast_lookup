require "net/http"

class AddressGeocoder
  class Error < StandardError; end
  class AddressNotFound < Error; end
  class ServiceUnavailable < Error; end

  Location = Data.define(:latitude, :longitude, :zip_code, :country_code, :display_name)

  ENDPOINT = URI("https://nominatim.openstreetmap.org/search")
  USER_AGENT = "forecast_lookup/1.0 (Rails take-home project)"
  OPEN_TIMEOUT_SECONDS = 3
  READ_TIMEOUT_SECONDS = 10
  NETWORK_ERRORS = [ Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError ].freeze
  UNAVAILABLE_MESSAGE = "The address lookup service is unavailable. Please try again later."

  def self.call(address)
    new(address).call
  end

  def initialize(address)
    @address = address
  end

  def call
    result = search.first
    raise AddressNotFound, "We could not find that address." if result.nil?

    build_location(result)
  end

  private

  def search
    response = fetch
    raise ServiceUnavailable, UNAVAILABLE_MESSAGE unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue *NETWORK_ERRORS
    raise ServiceUnavailable, UNAVAILABLE_MESSAGE
  end

  def fetch
    Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS) do |http|
      http.get(search_uri.request_uri, "User-Agent" => USER_AGENT)
    end
  end

  def search_uri
    ENDPOINT.dup.tap do |uri|
      uri.query = URI.encode_www_form(q: @address, format: "json", addressdetails: 1, limit: 1)
    end
  end

  def build_location(result)
    address = result.fetch("address", {})
    zip_code = address["postcode"]
    raise AddressNotFound, "That address has no zip code. Try a more specific address." if zip_code.blank?

    Location.new(
      latitude: Float(result["lat"]),
      longitude: Float(result["lon"]),
      zip_code: zip_code,
      country_code: address["country_code"],
      display_name: result["display_name"]
    )
  end
end
