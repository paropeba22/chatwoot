class TechnicalIncidents::OutboxDispatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless TechnicalIncidents::Configuration.outbox_enabled?

    recover_stuck_deliveries
    TechnicalIncidentDelivery.outbox_ready.order(:next_retry_at, :id).limit(200).pluck(:id).each do |delivery_id|
      TechnicalIncidents::OutboxProcessJob.perform_later(delivery_id)
    rescue StandardError => e
      TechnicalIncidents::Instrumentation.record(
        event: 'outbox.enqueue_failed',
        delivery_id: delivery_id,
        reason_code: e.class.name
      )
    end
  end

  private

  def recover_stuck_deliveries
    TechnicalIncidentDelivery.outbox_stuck.in_batches.update_all(
      outbox_state: 'retry',
      locked_at: nil,
      lock_token: nil,
      next_retry_at: Time.current,
      last_error_code: 'outbox_lease_expired',
      updated_at: Time.current
    )
  end
end
