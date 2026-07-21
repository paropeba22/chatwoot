class TechnicalIncidents::OutboxProcessJob < ApplicationJob
  queue_as :high

  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    TechnicalIncidents::OutboxProcessor.new(delivery_id).call
  end
end
