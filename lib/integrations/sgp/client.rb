class Integrations::Sgp::Client
  class Error < StandardError; end
  class ConfigurationError < Error; end

  DEFAULT_TIMEOUT = 15

  def perform(payload)
    validate_configuration!

    response = HTTParty.post(
      webhook_url,
      headers: {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'X-Chatwoot-SGP-Secret' => webhook_secret
      },
      body: payload.to_json,
      timeout: timeout
    )

    parsed = parsed_response(response)
    return parsed if response.code.to_i.between?(200, 299) || parsed[:ok] == false

    raise Error, "n8n returned HTTP #{response.code}"
  rescue JSON::ParserError => e
    raise Error, "invalid n8n response: #{e.message}"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, HTTParty::Error => e
    raise Error, e.message
  end

  private

  def parsed_response(response)
    body = response.parsed_response
    body = JSON.parse(response.body) unless body.is_a?(Hash)
    body.deep_symbolize_keys
  end

  def validate_configuration!
    return if webhook_url.present? && webhook_secret.present?

    raise ConfigurationError, 'n8n SGP integration is not configured'
  end

  def webhook_url
    ENV.fetch('N8N_CHATWOOT_WEBHOOK_URL', nil)
  end

  def webhook_secret
    ENV.fetch('N8N_CHATWOOT_WEBHOOK_SECRET', nil)
  end

  def timeout
    ENV.fetch('N8N_CHATWOOT_TIMEOUT_SECONDS', DEFAULT_TIMEOUT).to_i.clamp(1, 30)
  end
end
