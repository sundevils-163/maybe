module Security::Provided
  extend ActiveSupport::Concern

  SecurityInfoMissingError = Class.new(StandardError)

  class_methods do
    def primary_provider
      registry = Provider::Registry.for_concept(:securities)
      registry.get_provider(:synth)
    end

    def fallback_provider
      registry = Provider::Registry.for_concept(:securities)
      registry.get_provider(:fmp)
    end

    def available_providers
      [primary_provider, fallback_provider].compact
    end

    def search_provider(symbol, country_code: nil, exchange_operating_mic: nil)
      return [] if symbol.blank?

      params = {
        country_code: country_code,
        exchange_operating_mic: exchange_operating_mic
      }.compact_blank

      # Try primary provider first (Synth)
      if primary_provider.present?
        response = primary_provider.search_securities(symbol, **params)

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

      # Fallback to FMP if Synth fails or returns no results
      if fallback_provider.present?
        response = fallback_provider.search_securities(symbol, **params)

        if response.success?
          return response.data.map do |provider_security|
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
  end

  def find_or_fetch_price(date: Date.current, cache: true)
    price = prices.find_by(date: date)

    return price if price.present?

    # Try each available provider in order
    self.class.available_providers.each do |provider|
      next unless provider.present?

      response = provider.fetch_security_price(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic,
        date: date
      )

      next unless response.success? # Try next provider if this one fails

      price_data = response.data
      Security::Price.find_or_create_by!(
        security_id: self.id,
        date: price_data.date,
        price: price_data.price,
        currency: price_data.currency
      ) if cache
      return price_data
    end

    nil # All providers failed
  end

  def import_provider_details(clear_cache: false)
    if self.name.present? && self.logo_url.present? && !clear_cache
      return
    end

    # Try each available provider in order
    self.class.available_providers.each do |provider|
      next unless provider.present?

      response = provider.fetch_security_info(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic
      )

      if response.success?
        update(
          name: response.data.name,
          logo_url: response.data.logo_url,
        )
        return # Successfully updated, exit
      else
        Rails.logger.warn("Failed to fetch security info for #{ticker} from #{provider.class.name}: #{response.error.message}")
      end
    end

    # If all providers failed, capture exception
    Sentry.capture_exception(SecurityInfoMissingError.new("Failed to get security info from all providers"), level: :warning) do |scope|
      scope.set_tags(security_id: self.id)
      scope.set_context("security", { id: self.id, ticker: ticker })
    end
  end

  def import_provider_prices(start_date:, end_date:, clear_cache: false)
    total_imported = 0

    # Try each available provider in order
    self.class.available_providers.each do |provider|
      next unless provider.present?

      imported_count = Security::Price::Importer.new(
        security: self,
        security_provider: provider,
        start_date: start_date,
        end_date: end_date,
        clear_cache: clear_cache
      ).import_provider_prices

      if imported_count > 0
        total_imported += imported_count
        break # Successfully imported prices, exit
      else
        Rails.logger.warn("Provider #{provider.class.name} failed to import prices for #{ticker}")
      end
    end

    if total_imported == 0
      Rails.logger.warn("All providers failed to import prices for #{ticker}")  
    end

    total_imported
  end

  private
    def provider
      # For backward compatibility, return primary provider
      self.class.primary_provider
    end
end
