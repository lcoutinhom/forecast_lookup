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
  NOT_FOUND_MESSAGE = "We could not find that address."
  LATITUDE_RANGE = -90.0..90.0
  LONGITUDE_RANGE = -180.0..180.0

  def self.call(address)
    new(address).call
  end

  def initialize(address)
    @address = address
  end

  def call
    result = search.first
    raise AddressNotFound, NOT_FOUND_MESSAGE if result.nil?

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
    address = result["address"] || {}

    Location.new(
      latitude: coordinate(result["lat"], LATITUDE_RANGE),
      longitude: coordinate(result["lon"], LONGITUDE_RANGE),
      zip_code: address["postcode"].presence,
      country_code: address["country_code"],
      display_name: result["display_name"]
    )
  end

  def coordinate(value, range)
    number = Float(value, exception: false)
    raise AddressNotFound, NOT_FOUND_MESSAGE unless number&.finite? && range.cover?(number)

    number
  end
end
