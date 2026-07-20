class TechnicalIncidents::DeliveryRetryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(_delivery_id = nil)
    TechnicalIncidents::OutboxDispatchJob.perform_now
  end
end
