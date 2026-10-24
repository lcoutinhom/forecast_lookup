require "rails_helper"

RSpec.describe "Cache store" do
  it "uses an in-memory store" do
    expect(Rails.cache).to be_a(ActiveSupport::Cache::MemoryStore)
  end

  it "starts each example with an empty cache" do
    expect(Rails.cache.read("leftover")).to be_nil
    Rails.cache.write("leftover", true)
  end

  it "does not leak entries between examples" do
    expect(Rails.cache.read("leftover")).to be_nil
    Rails.cache.write("leftover", true)
  end
end
