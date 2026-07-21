class TechnicalIncidents::Configuration
  AUTOMATION_MODES = %w[disabled shadow active].freeze
  REQUEST_MODES = %w[shadow active].freeze

  class << self
    def automation_mode
      configured_mode('TECHNICAL_INCIDENTS_AUTOMATION_MODE')
    end

    def effective_mode(requested_mode)
      requested = requested_mode.to_s
      return 'disabled' unless REQUEST_MODES.include?(requested)
      return 'disabled' if automation_mode == 'disabled'
      return 'shadow' if automation_mode == 'shadow'

      requested
    end

    def outbox_enabled?
      boolean('TECHNICAL_INCIDENTS_OUTBOX_ENABLED')
    end

    def delivery_enabled?
      boolean('TECHNICAL_INCIDENTS_DELIVERY_ENABLED')
    end

    def api_inbox_delivery_enabled?
      boolean('TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED')
    end

    def medium_confidence
      confidence('TECHNICAL_INCIDENTS_MEDIUM_CONFIDENCE', 0.70)
    end

    def high_confidence
      confidence('TECHNICAL_INCIDENTS_HIGH_CONFIDENCE', 0.85)
    end

    def max_delivery_attempts
      ENV.fetch('TECHNICAL_INCIDENTS_MAX_DELIVERY_ATTEMPTS', '8').to_i.clamp(1, 20)
    end

    def outbox_lease
      ENV.fetch('TECHNICAL_INCIDENTS_OUTBOX_LEASE_SECONDS', '300').to_i.clamp(30, 3_600).seconds
    end

    private

    def configured_mode(key)
      value = ENV.fetch(key, 'disabled').to_s
      AUTOMATION_MODES.include?(value) ? value : 'disabled'
    end

    def boolean(key)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(key, 'false'))
    end

    def confidence(key, default)
      Float(ENV.fetch(key, default.to_s)).clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      default
    end
  end
end
