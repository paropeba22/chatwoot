class TechnicalIncidents::DeliveryStatusJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    TechnicalIncidentDelivery.where(state: %w[delivery_queued handoff_completed]).includes(:message).find_each do |delivery|
      next unless delivery.message

      if delivery.message.failed?
        delivery.update!(state: 'failed_retryable', last_error: delivery.message.content_attributes['external_error'].to_s.first(500))
      elsif delivery.message.delivered? || delivery.message.read?
        delivery.update!(state: 'delivered', delivered_at: Time.current)
      end
    end
  end
end
