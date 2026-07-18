class TechnicalIncidents::RetentionJob < ApplicationJob
  queue_as :purgable

  def perform
    TechnicalIncidentEvaluation.where('created_at < ?', 180.days.ago).in_batches do |batch|
      batch.update_all(
        classification: {},
        candidate_snapshot: [],
        sanitized_contracts: [],
        selected_contract: {},
        source_message_id: nil,
        feedback_note: nil,
        updated_at: Time.current
      )
    end
    TechnicalIncidentUpdate.where('created_at < ?', 5.years.ago).in_batches.delete_all
  end
end
