require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"

RSpec.configure do |config|
  config.use_active_record = false
  config.filter_rails_from_backtrace!
  config.include ActiveSupport::Testing::TimeHelpers

  config.before do
    Rails.cache.clear
  end
end
