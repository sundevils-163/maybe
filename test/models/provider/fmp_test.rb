require "test_helper"

class Provider::FmpTest < ActiveSupport::TestCase
  def setup
    @api_key = "test_api_key"
    @provider = Provider::Fmp.new(@api_key)
  end

  test "initializes with API key" do
    assert_equal @api_key, @provider.send(:api_key)
  end

  test "includes SecurityConcept" do
    assert @provider.class.included_modules.include?(Provider::SecurityConcept)
  end

  test "responds to required SecurityConcept methods" do
    assert_respond_to @provider, :search_securities
    assert_respond_to @provider, :fetch_security_info
    assert_respond_to @provider, :fetch_security_price
    assert_respond_to @provider, :fetch_security_prices
  end

  test "has correct base URL" do
    assert_equal "https://financialmodelingprep.com/api/v3", @provider.send(:base_url)
  end

  test "has custom error classes" do
    assert Provider::Fmp::Error < Provider::Error
    assert Provider::Fmp::InvalidSecurityPriceError < Provider::Fmp::Error
    assert Provider::Fmp::InvalidSecurityInfoError < Provider::Fmp::Error
  end

  test "determines security kind correctly" do
    # Test stock
    stock_data = { "isEtf" => false, "exchangeShortName" => "NASDAQ" }
    assert_equal "stock", @provider.send(:determine_security_kind, stock_data)

    # Test ETF
    etf_data = { "isEtf" => true, "exchangeShortName" => "NASDAQ" }
    assert_equal "etf", @provider.send(:determine_security_kind, etf_data)

    # Test mutual fund
    mutual_fund_data = { "isEtf" => false, "exchangeShortName" => "MUTUAL" }
    assert_equal "mutual_fund", @provider.send(:determine_security_kind, mutual_fund_data)
  end

  test "client has proper configuration" do
    client = @provider.send(:client)
    
    assert_instance_of Faraday::Connection, client
    assert_equal "https://financialmodelingprep.com/api/v3", client.url_prefix.to_s
    assert_equal "Maybe Finance App", client.headers["User-Agent"]
  end
end