class Provider::Fmp < Provider
  include SecurityConcept

  # Subclass so errors caught in this provider are raised as Provider::Fmp::Error
  Error = Class.new(Provider::Error)
  InvalidSecurityPriceError = Class.new(Error)
  InvalidSecurityInfoError = Class.new(Error)

  def initialize(api_key)
    @api_key = api_key
  end

  def healthy?
    with_provider_response do
      response = client.get("#{base_url}/profile/AAPL")
      parsed = JSON.parse(response.body)
      parsed.is_a?(Array) && parsed.any?
    end
  end

  # ================================
  #           Securities
  # ================================

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      response = client.get("#{base_url}/search") do |req|
        req.params["query"] = symbol
        req.params["limit"] = 25
        req.params["apikey"] = api_key
      end

      parsed = JSON.parse(response.body)

      (parsed || []).map do |security|
        Security.new(
          symbol: security.dig("symbol"),
          name: security.dig("name"),
          logo_url: nil, # FMP doesn't provide logo URLs in search
          exchange_operating_mic: security.dig("exchangeShortName"),
          country_code: country_code
        )
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      response = client.get("#{base_url}/profile/#{symbol}") do |req|
        req.params["apikey"] = api_key
      end

      data = JSON.parse(response.body)
      
      if data.is_a?(Array) && data.any?
        security_data = data.first
        
        SecurityInfo.new(
          symbol: symbol,
          name: security_data.dig("companyName"),
          links: security_data.dig("website") ? [security_data.dig("website")] : [],
          logo_url: security_data.dig("image"),
          description: security_data.dig("description"),
          kind: determine_security_kind(security_data),
          exchange_operating_mic: security_data.dig("exchangeShortName")
        )
      else
        raise ProviderError, "No security info found for #{symbol}"
      end
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      response = fetch_security_prices(symbol:, exchange_operating_mic:, start_date: date, end_date: date)

      if response.success?
        prices = response.data.paginated
        raise ProviderError, "No prices found for security #{symbol} on date #{date}" if prices.empty?
        prices.first
      else
        raise ProviderError, "Failed to fetch price for #{symbol} on #{date}: #{response.error.message}"
      end
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      response = client.get("#{base_url}/historical-price-full/#{symbol}") do |req|
        req.params["from"] = start_date.strftime("%Y-%m-%d")
        req.params["to"] = end_date.strftime("%Y-%m-%d")
        req.params["apikey"] = api_key
      end

      parsed = JSON.parse(response.body)
      historical_data = parsed.dig("historical") || []

      prices = historical_data.map do |price_data|
        date = Date.parse(price_data.dig("date"))
        close_price = price_data.dig("close")

        if date.nil? || close_price.nil?
          Rails.logger.warn("#{self.class.name} returned invalid price data for security #{symbol} on: #{date}. Price data: #{price_data.inspect}")
          Sentry.capture_exception(InvalidSecurityPriceError.new("#{self.class.name} returned invalid security price data"), level: :warning) do |scope|
            scope.set_context("security", { symbol: symbol, date: date })
          end

          next
        end

        Price.new(
          symbol: symbol,
          date: date,
          price: close_price,
          currency: "USD", # FMP typically returns USD prices
          exchange_operating_mic: exchange_operating_mic
        )
      end.compact

      PaginatedData.new(
        paginated: prices,
        first_page: parsed,
        total_pages: 1
      )
    end
  end

  private
    attr_reader :api_key

    def base_url
      "https://financialmodelingprep.com/api/v3"
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
        faraday.headers["User-Agent"] = "Maybe Finance App"
      end
    end

    def determine_security_kind(security_data)
      # Determine if it's a mutual fund, ETF, or stock based on available data
      security_type = security_data.dig("exchangeShortName")
      
      if security_type&.include?("MUTUAL") || security_data.dig("isEtf") == false
        "mutual_fund"
      elsif security_data.dig("isEtf") == true
        "etf"
      else
        "stock"
      end
    end
end