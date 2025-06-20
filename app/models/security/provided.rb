module Security::Provided
  extend ActiveSupport::Concern

  SecurityInfoMissingError = Class.new(StandardError)

  class_methods do
    def provider
      registry = Provider::Registry.for_concept(:securities)
      registry.get_provider(:synth)
    end

    def providers
      registry = Provider::Registry.for_concept(:securities)
      [
        registry.get_provider(:synth),
        registry.get_provider(:fmp)
      ].compact
    end

    def search_provider(symbol, country_code: nil, exchange_operating_mic: nil)
      return [] if symbol.blank?

      params = {
        country_code: country_code,
        exchange_operating_mic: exchange_operating_mic
      }.compact_blank

      # Try each provider in order until one succeeds
      providers.each do |provider|
        next unless provider.present?
        
        response = provider.search_securities(symbol, **params)

        if response.success? && response.data.any?
          return response.data.map do |provider_security|
            # Need to map to domain model so Combobox can display via to_combobox_option
            Security.new(
              ticker: provider_security.symbol,
              name: provider_security.name,
              logo_url: provider_security.logo_url,
              exchange_operating_mic: provider_security.exchange_operating_mic,
              country_code: provider_security.country_code
            )
          end
        end
      end

      []
    end

    private

    def try_provider_operation(operation_name, *args, **kwargs, &block)
      last_error = nil

      providers.each do |provider|
        next unless provider.present?

        begin
          response = provider.send(operation_name, *args, **kwargs)
          
          if response.success?
            return yield(response) if block_given?
            return response
          else
            last_error = response.error
          end
        rescue => e
          last_error = e
          Rails.logger.warn("Provider #{provider.class.name} failed for #{operation_name}: #{e.message}")
        end
      end

      # If we get here, all providers failed
      Rails.logger.warn("All providers failed for #{operation_name}. Last error: #{last_error}")
      nil
    end
  end

  def find_or_fetch_price(date: Date.current, cache: true)
    price = prices.find_by(date: date)

    return price if price.present?

    # Try each provider in order until one succeeds
    result = self.class.try_provider_operation(
      :fetch_security_price,
      symbol: ticker,
      exchange_operating_mic: exchange_operating_mic,
      date: date
    ) do |response|
      response.data
    end

    return nil unless result

    if cache
      Security::Price.find_or_create_by!(
        security_id: id,
        date: result.date,
        price: result.price,
        currency: result.currency
      )
    end
    
    result
  end

  def import_provider_details(clear_cache: false)
    if self.name.present? && self.logo_url.present? && !clear_cache
      return
    end

    # Try each provider in order until one succeeds
    success = self.class.try_provider_operation(
      :fetch_security_info,
      symbol: ticker,
      exchange_operating_mic: exchange_operating_mic
    ) do |response|
      update(
        name: response.data.name,
        logo_url: response.data.logo_url,
      )
      true
    end

    unless success
      Rails.logger.warn("Failed to fetch security info for #{ticker} from all providers")
      Sentry.capture_exception(SecurityInfoMissingError.new("Failed to get security info from all providers"), level: :warning) do |scope|
        scope.set_tags(security_id: self.id)
        scope.set_context("security", { id: self.id })
      end
    end
  end

  def import_provider_prices(start_date:, end_date:, clear_cache: false)
    # Try each provider in order until one succeeds
    imported_count = 0

    self.class.providers.each do |provider|
      next unless provider.present?

      begin
        imported_count = Security::Price::Importer.new(
          security: self,
          security_provider: provider,
          start_date: start_date,
          end_date: end_date,
          clear_cache: clear_cache
        ).import_provider_prices

        # If we successfully imported prices, break out of the loop
        break if imported_count > 0
      rescue => e
        Rails.logger.warn("Provider #{provider.class.name} failed to import prices for #{ticker}: #{e.message}")
      end
    end

    if imported_count == 0
      Rails.logger.warn("No provider was able to import prices for Security #{ticker}")
    end

    imported_count
  end

  private
    def provider
      self.class.provider
    end
end
