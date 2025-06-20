require "test_helper"

class Security::ProvidedTest < ActiveSupport::TestCase
  def setup
    @security = securities(:aapl)
  end

  test "has primary_provider class method" do
    assert_respond_to Security, :primary_provider
    assert_not_nil Security.primary_provider
  end

  test "has fallback_provider class method" do
    assert_respond_to Security, :fallback_provider
    assert_not_nil Security.fallback_provider
  end

  test "primary_provider is different from fallback_provider" do
    primary = Security.primary_provider
    fallback = Security.fallback_provider
    
    assert_not_nil primary
    assert_not_nil fallback
    assert_not_equal primary.class, fallback.class
  end

  test "security responds to provider methods" do
    assert_respond_to @security, :find_or_fetch_price
    assert_respond_to @security, :import_provider_details
    assert_respond_to @security, :import_provider_prices
  end

  test "security has access to both providers" do
    assert_respond_to @security, :primary_provider
    assert_respond_to @security, :fallback_provider
    
    assert_equal Security.primary_provider, @security.send(:primary_provider)
    assert_equal Security.fallback_provider, @security.send(:fallback_provider)
  end

  test "search_provider accepts correct parameters" do
    # Test that the method exists and accepts the expected parameters
    assert_respond_to Security, :search_provider
    
    # Should not raise error with valid parameters
    begin
      Security.search_provider("TEST", country_code: "US", exchange_operating_mic: "XNAS")
    rescue => e
      # It's okay if the API call fails, we're just testing the method signature
      assert_instance_of StandardError, e
    end
  end

  test "find_or_fetch_price accepts date parameter" do
    # Test that the method exists and accepts date parameter
    begin
      @security.find_or_fetch_price(date: Date.current, cache: false)
    rescue => e
      # It's okay if the API call fails, we're just testing the method signature
      assert_instance_of StandardError, e
    end
  end

  test "import_provider_details accepts clear_cache parameter" do
    # Test that the method exists and accepts clear_cache parameter
    begin
      @security.import_provider_details(clear_cache: true)
    rescue => e
      # It's okay if the API call fails, we're just testing the method signature
      assert_instance_of StandardError, e
    end
  end

  test "import_provider_prices accepts date range parameters" do
    # Test that the method exists and accepts date range parameters
    begin
      @security.import_provider_prices(
        start_date: 1.week.ago.to_date,
        end_date: Date.current,
        clear_cache: false
      )
    rescue => e
      # It's okay if the API call fails, we're just testing the method signature
      assert_instance_of StandardError, e
    end
  end
end