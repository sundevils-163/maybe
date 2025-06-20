# Financial Data Providers

The Maybe application supports multiple financial data providers for retrieving stock prices, mutual fund data, and other financial information. This document explains how to configure and use these providers.

## Supported Providers

### 1. Synth (Primary Provider)
- **Purpose**: Primary provider for exchange rates and stock prices
- **Configuration**: Set `SYNTH_API_KEY` environment variable or configure in self-hosted settings
- **Website**: https://synthfinance.com/
- **Strengths**: Comprehensive stock data, exchange rates
- **Limitations**: Limited support for mutual funds

### 2. Financial Modeling Prep (FMP) (Fallback Provider)
- **Purpose**: Fallback provider for stock prices, particularly useful for mutual funds and ETFs
- **Configuration**: Set `FMP_API_KEY` environment variable or configure in self-hosted settings  
- **Website**: https://financialmodelingprep.com/
- **Strengths**: Extensive mutual fund and ETF support, comprehensive financial data
- **API Documentation**: https://site.financialmodelingprep.com/developer/docs/stable

## Fallback Logic

The application implements a fallback mechanism for stock price retrieval:

1. **Primary**: Synth API is tried first for all stock price requests
2. **Fallback**: If Synth fails or doesn't have data, FMP API is used automatically
3. **Offline**: If both providers fail, the security is marked as "offline"

This ensures maximum coverage, especially for mutual funds and ETFs that may not be available in Synth.

## Configuration

### Environment Variables
```bash
# Primary provider
SYNTH_API_KEY=your_synth_api_key_here

# Fallback provider  
FMP_API_KEY=your_fmp_api_key_here
```

### Self-Hosted Settings
For self-hosted installations, you can configure API keys through the web interface:
1. Navigate to Settings → Self-Hosting
2. Configure keys in the "General Settings" section
3. Both Synth and FMP settings are available

## API Rate Limits

- **Synth**: Rate limits vary by plan (shown in settings UI)
- **FMP**: Rate limits vary by plan (typically 250-300 requests/minute for free tier)

Be mindful of rate limits when importing large amounts of historical data.

## Supported Operations

Both providers support:
- Security search by symbol
- Real-time price fetching
- Historical price data
- Company profile information

## Testing

To test the providers:
1. Set up API keys in test environment
2. Run provider-specific tests: `rails test test/models/provider/synth_test.rb`
3. Run provider-specific tests: `rails test test/models/provider/fmp_test.rb`

Note: Tests will be skipped if API keys are not provided.