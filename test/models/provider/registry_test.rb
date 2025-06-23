require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "synth configured with ENV" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "123" do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth configured with Setting" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth not configured" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:synth)
    end
  end

  test "fmp configured with ENV" do
    Setting.stubs(:fmp_api_key).returns(nil)

    with_env_overrides FMP_API_KEY: "123" do
      assert_instance_of Provider::Fmp, Provider::Registry.get_provider(:fmp)
    end
  end

  test "fmp configured with Setting" do
    Setting.stubs(:fmp_api_key).returns("123")

    with_env_overrides FMP_API_KEY: nil do
      assert_instance_of Provider::Fmp, Provider::Registry.get_provider(:fmp)
    end
  end

  test "fmp not configured" do
    Setting.stubs(:fmp_api_key).returns(nil)

    with_env_overrides FMP_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:fmp)
    end
  end

  test "can get synth provider" do
    Setting.stubs(:synth_api_key).returns("test_key")
    
    registry = Provider::Registry.for_concept(:securities)
    provider = registry.get_provider(:synth)

    assert provider.is_a?(Provider::Synth)
  end

  test "can get fmp provider" do
    Setting.stubs(:fmp_api_key).returns("test_key")
    
    registry = Provider::Registry.for_concept(:securities)
    provider = registry.get_provider(:fmp)

    assert provider.is_a?(Provider::Fmp)
  end

  test "returns nil for synth provider when api key not set" do
    ENV.stub(:fetch, nil) do
      Setting.stub(:synth_api_key, nil) do
        registry = Provider::Registry.for_concept(:securities)
        provider = registry.get_provider(:synth)

        assert_nil provider
      end
    end
  end

  test "returns nil for fmp provider when api key not set" do
    ENV.stub(:fetch, nil) do
      Setting.stub(:fmp_api_key, nil) do
        registry = Provider::Registry.for_concept(:securities)
        provider = registry.get_provider(:fmp)

        assert_nil provider
      end
    end
  end

  test "securities concept includes both synth and fmp providers" do
    Setting.stubs(:synth_api_key).returns("test_key")
    Setting.stubs(:fmp_api_key).returns("test_key")
    
    registry = Provider::Registry.for_concept(:securities)
    providers = registry.providers

    assert_includes providers.map(&:class), Provider::Synth
    assert_includes providers.map(&:class), Provider::Fmp
  end

  test "providers are returned in correct order" do
    Setting.stubs(:synth_api_key).returns("test_key")
    Setting.stubs(:fmp_api_key).returns("test_key")
    
    registry = Provider::Registry.for_concept(:securities)
    providers = registry.providers

    # Synth should come first, then FMP
    assert_equal Provider::Synth, providers[0].class
    assert_equal Provider::Fmp, providers[1].class
  end
end
