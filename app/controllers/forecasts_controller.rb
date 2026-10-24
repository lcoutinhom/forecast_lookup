class ForecastsController < ApplicationController
  def show
    @address = params[:address].to_s.strip
    search if params.key?(:address)
  end

  private

  def search
    return render_error("Please enter an address.", :unprocessable_content) if @address.blank?

    @result = ForecastSearch.call(@address)
  rescue AddressGeocoder::AddressNotFound => error
    render_error(error.message, :unprocessable_content)
  rescue AddressGeocoder::ServiceUnavailable, WeatherForecaster::Error => error
    render_error(error.message, :service_unavailable)
  end

  def render_error(message, status)
    @error = message
    render :show, status: status
  end
end
