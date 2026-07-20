class TechnicalIncidents::DeliveryStatusJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless TechnicalIncidents::Configuration.outbox_enabled?

    TechnicalIncidentDelivery.where(transport_state: 'queued').includes(:message).find_each do |delivery|
      next unless delivery.message

      delivery.with_lock do
        if delivery.message.failed?
          delivery.update!(
            transport_state: 'failed_retryable',
            outbox_state: 'retry',
            next_retry_at: Time.current,
            last_error_code: 'transport_failed',
            last_error: delivery.message.content_attributes['external_error'].to_s.first(500)
          )
        elsif delivery.message.delivered? || delivery.message.read?
          delivery.update!(
            transport_state: 'delivered',
            state: 'delivered',
            delivered_at: Time.current,
            outbox_state: 'retry',
            next_retry_at: Time.current
          )
        end
      end
    rescue StandardError => e
      TechnicalIncidents::Instrumentation.record(
        event: 'delivery.status_failed',
        delivery_id: delivery.id,
        reason_code: e.class.name
      )
    end
  ensure
    TechnicalIncidents::OutboxDispatchJob.perform_later if TechnicalIncidents::Configuration.outbox_enabled?
  end
end
