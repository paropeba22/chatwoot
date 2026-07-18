class TechnicalIncidents::DeliveryRetryJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(delivery_id = nil)
    scope = delivery_id ? TechnicalIncidentDelivery.where(id: delivery_id) : TechnicalIncidentDelivery.retryable
    scope.find_each do |delivery|
      next unless delivery.account.feature_enabled?('technical_incidents')
      next unless delivery.message

      delivery.with_lock do
        delivery.increment!(:attempts)
        SendReplyJob.perform_later(delivery.message_id)
        delivery.update!(state: 'delivery_queued', delivery_queued_at: Time.current, last_error: nil)
      end
    rescue StandardError => e
      delivery.update!(
        state: delivery.attempts >= 5 ? 'failed_terminal' : 'failed_retryable',
        last_error: e.class.name
      )
      raise
    end
  end
end
