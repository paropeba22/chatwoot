class TechnicalIncidents::Instrumentation
  ALLOWED_KEYS = %i[
    event request_id evaluation_id incident_id conversation_id delivery_id outbox_id
    reason_code status match_source duration_ms attempt provider
  ].freeze

  def self.record(attributes)
    payload = attributes.to_h.symbolize_keys.slice(*ALLOWED_KEYS).compact
    payload[:event] = "technical_incidents.#{payload.fetch(:event)}"
    ActiveSupport::Notifications.instrument(payload[:event], payload.except(:event))
    Rails.logger.info(payload.to_json)
  end

  def self.measure(event, attributes = {})
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    record(attributes.merge(event: event, status: 'ok', duration_ms: elapsed_ms(started_at)))
    result
  rescue StandardError => e
    record(attributes.merge(event: event, status: 'error', reason_code: e.class.name, duration_ms: elapsed_ms(started_at)))
    raise
  end

  def self.elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
  end

  private_class_method :elapsed_ms
end
