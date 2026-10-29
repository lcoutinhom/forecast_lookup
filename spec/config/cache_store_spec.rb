require "rails_helper"
require "open3"

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

  it "expires entries after their TTL" do
    travel_to(Time.zone.local(2026, 10, 24, 12, 0)) { Rails.cache.write("entry", true, expires_in: 30.minutes) }

    expect(travel_to(Time.zone.local(2026, 10, 24, 12, 29)) { Rails.cache.read("entry") }).to be(true)
    expect(travel_to(Time.zone.local(2026, 10, 24, 12, 31)) { Rails.cache.read("entry") }).to be_nil
  end

  describe "production" do
    it "stores Solid Cache entries in the cache database" do
      cache_database = ActiveRecord::Base.configurations.configs_for(env_name: "production", name: "cache")

      expect(Rails.application.config_for(:cache, env: "production")).to include(database: "cache")
      expect(cache_database).to have_attributes(database: "storage/production_cache.sqlite3", migrations_paths: "db/cache_migrate")
      expect(Rails.root.join("db/cache_schema.rb")).to exist
    end

    it "boots with Solid Cache as the cache store" do
      output, status = Open3.capture2e(
        { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" },
        "bin/rails", "runner", "print Rails.cache.class.name",
        chdir: Rails.root.to_s
      )

      expect(status).to be_success, output
      expect(output).to end_with("SolidCache::Store")
    end
  end
end
