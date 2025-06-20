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
end
