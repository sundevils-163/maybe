require "test_helper"
require "ostruct"

class Provider::FmpTest < ActiveSupport::TestCase
  include SecurityProviderInterfaceTest

  setup do
    @subject = @fmp = Provider::Fmp.new(ENV["FMP_API_KEY"])
  end

  test "health check" do
    skip "No FMP API key provided" unless ENV["FMP_API_KEY"].present?
    
    VCR.use_cassette("fmp/health") do
      assert @fmp.healthy?
    end
  end

  test "can be initialized with API key" do
    provider = Provider::Fmp.new("test_api_key")
    assert_equal "test_api_key", provider.send(:api_key)
  end

  test "search securities returns proper data structure" do
    skip "No FMP API key provided" unless ENV["FMP_API_KEY"].present?
    
    VCR.use_cassette("fmp/search_securities") do
      result = @fmp.search_securities("AAPL")
      
      if result.success?
        assert result.data.is_a?(Array)
        assert result.data.all? { |item| item.respond_to?(:symbol) }
        assert result.data.all? { |item| item.respond_to?(:name) }
      end
    end
  end

  test "fetch security price returns proper data structure" do
    skip "No FMP API key provided" unless ENV["FMP_API_KEY"].present?
    
    VCR.use_cassette("fmp/security_price") do
      result = @fmp.fetch_security_price(symbol: "AAPL", date: Date.current)
      
      if result.success?
        assert result.data.respond_to?(:symbol)
        assert result.data.respond_to?(:date)
        assert result.data.respond_to?(:price)
        assert result.data.respond_to?(:currency)
      end
    end
  end
end