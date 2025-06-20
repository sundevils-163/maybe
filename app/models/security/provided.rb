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

    # Try primary provider first (Synth)
    if primary_provider.present?
      response = primary_provider.fetch_security_price(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic,
        date: date
      )

      if response.success?
        provider_price = response.data
        Security::Price.find_or_create_by!(
          security_id: self.id,
          date: provider_price.date,
          price: provider_price.price,
          currency: provider_price.currency
        ) if cache
        return provider_price
      end
    end

    # Fallback to FMP if Synth fails
    if fallback_provider.present?
      response = fallback_provider.fetch_security_price(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic,
        date: date
      )

      if response.success?
        provider_price = response.data
        Security::Price.find_or_create_by!(
          security_id: self.id,
          date: provider_price.date,
          price: provider_price.price,
          currency: provider_price.currency
        ) if cache
        return provider_price
      end
    end

    nil # Both providers failed
  end

  def import_provider_details(clear_cache: false)
    if self.name.present? && self.logo_url.present? && !clear_cache
      return
    end

    # Try primary provider first (Synth)
    if primary_provider.present?
      response = primary_provider.fetch_security_info(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic
      )

      if response.success?
        update(
          name: response.data.name,
          logo_url: response.data.logo_url,
        )
        return
      else
        Rails.logger.warn("Primary provider (#{primary_provider.class.name}) failed to fetch security info for #{ticker}: #{response.error.message}")
      end
    end

    # Fallback to FMP if Synth fails
    if fallback_provider.present?
      response = fallback_provider.fetch_security_info(
        symbol: ticker,
        exchange_operating_mic: exchange_operating_mic
      )

      if response.success?
        update(
          name: response.data.name,
          logo_url: response.data.logo_url,
        )
        return
      else
        Rails.logger.warn("Fallback provider (#{fallback_provider.class.name}) failed to fetch security info for #{ticker}: #{response.error.message}")
      end
    end

    # Both providers failed
    Rails.logger.warn("Both providers failed to fetch security info for #{ticker}")
    Sentry.capture_exception(SecurityInfoMissingError.new("Failed to get security info from all providers"), level: :warning) do |scope|
      scope.set_tags(security_id: self.id)
      scope.set_context("security", { id: self.id, providers_tried: "synth, fmp" })
    end
  end

  def import_provider_prices(start_date:, end_date:, clear_cache: false)
    # Try primary provider first (Synth)
    if primary_provider.present?
      count = Security::Price::Importer.new(
        security: self,
        security_provider: primary_provider,
        start_date: start_date,
        end_date: end_date,
        clear_cache: clear_cache
      ).import_provider_prices

      return count if count > 0
    end

    # Fallback to FMP if Synth fails or returns no data
    if fallback_provider.present?
      Rails.logger.info("Falling back to FMP provider for #{ticker} price import")
      return Security::Price::Importer.new(
        security: self,
        security_provider: fallback_provider,
        start_date: start_date,
        end_date: end_date,
        clear_cache: clear_cache
      ).import_provider_prices
    end

    Rails.logger.warn("No providers available for Security.import_provider_prices")
    0
  end

  private
    def primary_provider
      self.class.primary_provider
    end

    def fallback_provider
      self.class.fallback_provider
    end
end
