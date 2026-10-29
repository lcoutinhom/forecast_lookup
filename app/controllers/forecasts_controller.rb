class ForecastsController < ApplicationController
  rescue_from ActionController::ParameterMissing do
    render_error("Please enter an address.", :bad_request)
  end

  rescue_from AddressGeocoder::AddressNotFound do |error|
    render_error(error.message, :not_found)
  end

  rescue_from AddressGeocoder::ServiceUnavailable, WeatherForecaster::Error do |error|
    render_error(error.message, :service_unavailable)
  end

  def show
    @address = params[:address].to_s.strip

    respond_to do |format|
      format.html { @result = search if params.key?(:address) }
      format.json { render json: search }
    end
  end

  private

  def search
    ForecastSearch.call(params.expect(:address).strip)
  end

  def render_error(message, status)
    @error = message

    respond_to do |format|
      format.html { render :show, status: status }
      format.json { render json: { error: message }, status: status }
    end
  end
end
