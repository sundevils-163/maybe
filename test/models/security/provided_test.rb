require "test_helper"

class Security::ProvidedTest < ActiveSupport::TestCase
  setup do
    @security = Security.create!(ticker: "VTSAX", name: "Vanguard Total Stock Market Index Fund")
  end

  test "search_provider falls back to FMP when Synth returns no results" do
    # Mock Synth to return empty results
    synth_provider = mock
    synth_response = Provider::Response.new(success?: true, data: [], error: nil)
    synth_provider.expects(:search_securities).returns(synth_response)

    # Mock FMP to return results
    fmp_provider = mock
    fmp_response = Provider::Response.new(
      success?: true, 
      data: [
        Provider::SecurityConcept::Security.new(
          symbol: "VTSAX",
          name: "Vanguard Total Stock Market Index Fund",
          logo_url: nil,
          exchange_operating_mic: "XNAS",
          country_code: "US"
        )
      ], 
      error: nil
    )
    fmp_provider.expects(:search_securities).returns(fmp_response)

    # Mock the registry to return our mocked providers
    registry = mock
    registry.expects(:get_provider).with(:synth).returns(synth_provider).at_least_once
    registry.expects(:get_provider).with(:fmp).returns(fmp_provider).at_least_once
    Provider::Registry.expects(:for_concept).with(:securities).returns(registry).at_least_once

    # Test the search
    results = Security.search_provider("VTSAX")

    assert_equal 1, results.length
    assert_equal "VTSAX", results.first.ticker
    assert_equal "Vanguard Total Stock Market Index Fund", results.first.name
  end

  test "try_provider_operation falls back to FMP when Synth fails" do
    # Mock Synth to fail
    synth_provider = mock
    synth_response = Provider::Response.new(success?: false, data: nil, error: "Not found")
    synth_provider.expects(:fetch_security_price).returns(synth_response)

    # Mock FMP to succeed
    fmp_provider = mock
    fmp_response = Provider::Response.new(
      success?: true, 
      data: Provider::SecurityConcept::Price.new(
        symbol: "VTSAX",
        date: Date.current,
        price: 100.0,
        currency: "USD",
        exchange_operating_mic: "XNAS"
      ), 
      error: nil
    )
    fmp_provider.expects(:fetch_security_price).returns(fmp_response)

    # Mock the registry to return our mocked providers
    registry = mock
    registry.expects(:get_provider).with(:synth).returns(synth_provider).at_least_once
    registry.expects(:get_provider).with(:fmp).returns(fmp_provider).at_least_once
    Provider::Registry.expects(:for_concept).with(:securities).returns(registry).at_least_once

    # Test the operation
    result = Security.try_provider_operation(:fetch_security_price, symbol: "VTSAX", date: Date.current) do |response|
      response.data
    end

    assert_not_nil result
    assert_equal "VTSAX", result.symbol
    assert_equal 100.0, result.price
  end

  test "providers method returns both synth and fmp providers" do
    # Mock the registry to return our mocked providers
    registry = mock
    registry.expects(:get_provider).with(:synth).returns(mock).at_least_once
    registry.expects(:get_provider).with(:fmp).returns(mock).at_least_once
    Provider::Registry.expects(:for_concept).with(:securities).returns(registry).at_least_once

    providers = Security.providers

    assert_equal 2, providers.length
    assert providers.all?(&:present?)
  end
end 