class TechnicalIncidents::DeliveryStatusJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless TechnicalIncidents::Configuration.outbox_enabled?

    TechnicalIncidentDelivery.where(transport_state: 'queued').includes(:message).find_each do |delivery|
      TechnicalIncidents::DeliveryStatusProcessor.new(delivery).call
    rescue StandardError => e
      record_failure(delivery, e)
    end
  ensure
    TechnicalIncidents::OutboxDispatchJob.perform_later if TechnicalIncidents::Configuration.outbox_enabled?
  end

  private

  def record_failure(delivery, error)
    TechnicalIncidents::Instrumentation.record(
      event: 'delivery.status_failed',
      delivery_id: delivery.id,
      reason_code: error.class.name
    )
  end
end
