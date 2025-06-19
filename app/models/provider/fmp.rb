class Provider::Fmp < Provider
  include SecurityConcept

  # Subclass so errors caught in this provider are raised as Provider::Fmp::Error
  Error = Class.new(Provider::Error)
  InvalidSecurityPriceError = Class.new(Error)

  def initialize(api_key)
    @api_key = api_key
  end

  def healthy?
    with_provider_response do
      response = client.get("#{base_url}/search")
      response.status == 200
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

      # Handle case where API returns an array directly
      results = parsed.is_a?(Array) ? parsed : []

      results.map do |security|
        # Filter by country code if specified
        next if country_code.present? && security["exchangeShortName"]&.downcase != country_code.downcase

        Security.new(
          symbol: security["symbol"],
          name: security["name"],
          logo_url: nil, # FMP doesn't provide logo URLs in search results
          exchange_operating_mic: security["exchangeShortName"],
          country_code: security["exchangeShortName"]
        )
      end.compact
    end
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      response = client.get("#{base_url}/profile/#{symbol}") do |req|
        req.params["apikey"] = api_key
      end

      data = JSON.parse(response.body)
      
      # Handle case where API returns an array with single item
      company_data = data.is_a?(Array) ? data.first : data

      return nil unless company_data

      SecurityInfo.new(
        symbol: symbol,
        name: company_data["companyName"] || company_data["name"],
        links: company_data["website"] ? [company_data["website"]] : [],
        logo_url: company_data["image"],
        description: company_data["description"],
        kind: determine_security_kind(company_data),
        exchange_operating_mic: exchange_operating_mic
      )
    end
  end

  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      historical_data = fetch_security_prices(symbol:, exchange_operating_mic:, start_date: date, end_date: date)

      raise ProviderError, "No prices found for security #{symbol} on date #{date}" if historical_data.empty?

      historical_data.first
    end
  end

  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      response = client.get("#{base_url}/historical-price-full/#{symbol}") do |req|
        req.params["from"] = start_date.to_s
        req.params["to"] = end_date.to_s
        req.params["apikey"] = api_key
      end

      data = JSON.parse(response.body)
      
      # Handle different response formats
      historical_data = if data["historical"]
        data["historical"]
      elsif data.is_a?(Array)
        data
      else
        []
      end

      # Get currency and exchange info from the main data or default to USD
      currency = data["symbol"]&.include?(".") ? determine_currency_from_exchange(data["symbol"]) : "USD"
      
      historical_data.map do |price_data|
        date = price_data["date"]
        price = price_data["close"] || price_data["adjClose"]

        if date.nil? || price.nil?
          Rails.logger.warn("#{self.class.name} returned invalid price data for security #{symbol} on: #{date}.  Price data: #{price.inspect}")
          Sentry.capture_exception(InvalidSecurityPriceError.new("#{self.class.name} returned invalid security price data"), level: :warning) do |scope|
            scope.set_context("security", { symbol: symbol, date: date })
          end

          next
        end

        Price.new(
          symbol: symbol,
          date: Date.parse(date),
          price: price.to_f,
          currency: currency,
          exchange_operating_mic: exchange_operating_mic
        )
      end.compact
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

    def determine_security_kind(company_data)
      # Try to determine if it's a mutual fund, ETF, or stock
      return "etf" if company_data["isEtf"] == true
      return "mutual_fund" if company_data["isFund"] == true || company_data["sector"]&.downcase&.include?("fund")
      return "stock" # Default to stock
    end

    def determine_currency_from_exchange(symbol)
      # Simple mapping of common exchange suffixes to currencies
      exchange_currency_map = {
        ".L" => "GBP",    # London Stock Exchange
        ".TO" => "CAD",   # Toronto Stock Exchange
        ".PA" => "EUR",   # Euronext Paris
        ".MI" => "EUR",   # Borsa Italiana
        ".AS" => "EUR",   # Euronext Amsterdam
        ".BR" => "EUR",   # Euronext Brussels
        ".SW" => "CHF",   # SIX Swiss Exchange
        ".T" => "JPY",    # Tokyo Stock Exchange
        ".HK" => "HKD",   # Hong Kong Stock Exchange
        ".AX" => "AUD",   # Australian Securities Exchange
      }

      suffix = exchange_currency_map.keys.find { |s| symbol.end_with?(s) }
      suffix ? exchange_currency_map[suffix] : "USD"
    end
end