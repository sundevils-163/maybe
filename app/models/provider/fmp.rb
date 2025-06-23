class Provider::Fmp < Provider
  include Provider::SecurityConcept

  # Subclass so errors caught in this provider are raised as Provider::Fmp::Error
  Error = Class.new(Provider::Error)
  InvalidSecurityPriceError = Class.new(Error)

  def initialize(api_key)
    @api_key = api_key
    Rails.logger.info("FMP provider initialized with API key: #{api_key.present? ? 'present' : 'missing'}")
  end

  def healthy?
    with_provider_response do
      begin
        # Test with a simple quote request
        response = client.get("#{base_url}/quote/AAPL") do |req|
          req.params["apikey"] = api_key
        end
        parsed = JSON.parse(response.body)
        parsed.is_a?(Array) && parsed.any?
      rescue Faraday::UnauthorizedError => e
        Rails.logger.error("FMP API 401 Unauthorized error in health check: #{e.message}")
        Rails.logger.error("FMP API key being used: #{api_key.present? ? 'present' : 'missing'}")
        false
      end
    end
  end

  # ================================
  #           Securities
  # ================================

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      Rails.logger.info("FMP searching for symbol: #{symbol} with API key: #{api_key.present? ? 'present' : 'missing'}")
      
      begin
        response = client.get("#{base_url}/search") do |req|
          req.params["query"] = symbol
          req.params["apikey"] = api_key
          req.params["limit"] = 25
        end

        parsed = JSON.parse(response.body)
        Rails.logger.info("FMP search returned #{parsed.length} results for symbol: #{symbol}")

        # Filter results based on country_code and exchange_operating_mic if provided
        results = parsed.select do |security|
          country_match = country_code.nil? || security["country"]&.upcase == country_code.upcase
          exchange_match = exchange_operating_mic.nil? || security["exchangeShortName"]&.upcase == exchange_operating_mic.upcase
          country_match && exchange_match
        end

        Rails.logger.info("FMP search filtered to #{results.length} results for symbol: #{symbol}")

        results.map do |security|
          Provider::SecurityConcept::Security.new(
            symbol: security["symbol"],
            name: security["name"],
            logo_url: nil, # FMP search doesn't include logo URLs
            exchange_operating_mic: security["exchangeShortName"],
            country_code: security["country"]
          )
        end
      rescue Faraday::UnauthorizedError => e
        Rails.logger.error("FMP API 401 Unauthorized error: #{e.message}")
        Rails.logger.error("FMP API key being used: #{api_key.present? ? 'present' : 'missing'}")
        raise ProviderError, "FMP API authentication failed. Please check your API key."
      end
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      Rails.logger.info("FMP fetching security info for symbol: #{symbol} with API key: #{api_key.present? ? 'present' : 'missing'}")
      
      begin
        response = client.get("#{base_url}/profile/#{symbol}") do |req|
          req.params["apikey"] = api_key
        end

        data = JSON.parse(response.body)
        
        # FMP returns an array, take the first result
        security_data = data.is_a?(Array) ? data.first : data
        
        raise ProviderError, "No profile data found for #{symbol}" if security_data.nil?

        Provider::SecurityConcept::SecurityInfo.new(
          symbol: symbol,
          name: security_data["companyName"],
          links: security_data["website"] ? [security_data["website"]] : [],
          logo_url: security_data["image"],
          description: security_data["description"],
          kind: security_data["isEtf"] ? "etf" : "stock",
          exchange_operating_mic: exchange_operating_mic
        )
      rescue Faraday::UnauthorizedError => e
        Rails.logger.error("FMP API 401 Unauthorized error: #{e.message}")
        Rails.logger.error("FMP API key being used: #{api_key.present? ? 'present' : 'missing'}")
        raise ProviderError, "FMP API authentication failed. Please check your API key."
      end
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      Rails.logger.info("FMP fetching security price for symbol: #{symbol} on date: #{date} with API key: #{api_key.present? ? 'present' : 'missing'}")
      
      begin
        if date == Date.current
          # Use real-time quote for current date
          response = client.get("#{base_url}/quote/#{symbol}") do |req|
            req.params["apikey"] = api_key
          end

          data = JSON.parse(response.body)
          price_data = data.is_a?(Array) ? data.first : data

          raise ProviderError, "No price data found for #{symbol}" if price_data.nil?

          Provider::SecurityConcept::Price.new(
            symbol: symbol,
            date: date,
            price: price_data["price"],
            currency: "USD", # FMP primarily uses USD
            exchange_operating_mic: exchange_operating_mic
          )
        else
          # Use historical data for past dates
          historical_data = fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date, end_date: date)
          
          raise ProviderError, "No prices found for security #{symbol} on date #{date}" if historical_data.empty?

          historical_data.first
        end
      rescue Faraday::UnauthorizedError => e
        Rails.logger.error("FMP API 401 Unauthorized error: #{e.message}")
        Rails.logger.error("FMP API key being used: #{api_key.present? ? 'present' : 'missing'}")
        raise ProviderError, "FMP API authentication failed. Please check your API key."
      end
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      Rails.logger.info("FMP fetching security prices for symbol: #{symbol} from #{start_date} to #{end_date} with API key: #{api_key.present? ? 'present' : 'missing'}")
      
      begin
        # For date ranges, use historical price endpoint
        response = client.get("#{base_url}/historical-price-full/#{symbol}") do |req|
          req.params["apikey"] = api_key
          req.params["from"] = start_date.to_s
          req.params["to"] = end_date.to_s
        end

        data = JSON.parse(response.body)
        historical_data = data["historical"] || []

        prices = historical_data.map do |price_data|
          date = Date.parse(price_data["date"])
          price = price_data["close"] || price_data["adjClose"]

          if date.nil? || price.nil?
            Rails.logger.warn("#{self.class.name} returned invalid price data for security #{symbol} on: #{date}. Price data: #{price.inspect}")
            Sentry.capture_exception(InvalidSecurityPriceError.new("#{self.class.name} returned invalid security price data"), level: :warning) do |scope|
              scope.set_context("security", { symbol: symbol, date: date })
            end
            next
          end

          Provider::SecurityConcept::Price.new(
            symbol: symbol,
            date: date,
            price: price,
            currency: "USD", # FMP primarily uses USD
            exchange_operating_mic: exchange_operating_mic
          )
        end.compact

        # Return array to match interface (like Synth provider)
        prices
      rescue Faraday::UnauthorizedError => e
        Rails.logger.error("FMP API 401 Unauthorized error: #{e.message}")
        Rails.logger.error("FMP API key being used: #{api_key.present? ? 'present' : 'missing'}")
        raise ProviderError, "FMP API authentication failed. Please check your API key."
      end
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
end