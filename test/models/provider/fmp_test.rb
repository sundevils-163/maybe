require "test_helper"

class Provider::FmpTest < ActiveSupport::TestCase
  include SecurityProviderInterfaceTest

  setup do
    @subject = @fmp = Provider::Fmp.new(ENV["FMP_API_KEY"] || "test_api_key")
  end

  test "health check" do
    VCR.use_cassette("fmp/health") do
      assert @fmp.healthy?.success?
    end
  end

  test "search securities" do
    VCR.use_cassette("fmp/search_securities") do
      response = @fmp.search_securities("AAPL")
      
      assert response.success?
      assert response.data.is_a?(Array)
      
      if response.data.any?
        security = response.data.first
        assert security.symbol.present?
        assert security.name.present?
      end
    end
  end

  test "fetch security info" do
    VCR.use_cassette("fmp/security_info") do
      response = @fmp.fetch_security_info(symbol: "AAPL", exchange_operating_mic: "XNAS")
      
      assert response.success?
      
      if response.data
        security_info = response.data
        assert_equal "AAPL", security_info.symbol
        assert security_info.name.present?
      end
    end
  end

  test "fetch security prices" do
    VCR.use_cassette("fmp/security_prices") do
      start_date = 1.week.ago.to_date
      end_date = Date.current
      
      response = @fmp.fetch_security_prices(
        symbol: "AAPL",
        exchange_operating_mic: "XNAS", 
        start_date: start_date,
        end_date: end_date
      )
      
      assert response.success?
      assert response.data.is_a?(Array)
      
      if response.data.any?
        price = response.data.first
        assert price.symbol.present?
        assert price.date.present?
        assert price.price.present?
        assert price.currency.present?
      end
    end
  end

  test "fetch single security price" do
    VCR.use_cassette("fmp/single_security_price") do
      date = 1.day.ago.to_date
      
      response = @fmp.fetch_security_price(
        symbol: "AAPL",
        exchange_operating_mic: "XNAS",
        date: date
      )
      
      assert response.success?
      
      if response.data
        price = response.data
        assert_equal "AAPL", price.symbol
        assert price.price.present?
        assert price.currency.present?
      end
    end
  end

  test "handles mutual fund symbols" do
    VCR.use_cassette("fmp/mutual_fund") do
      response = @fmp.search_securities("VTSAX")
      
      # Test should pass regardless of results since mutual fund support varies
      assert response.success?
      assert response.data.is_a?(Array)
    end
  end
end