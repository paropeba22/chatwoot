class TechnicalIncidents::RetentionJob < ApplicationJob
  queue_as :purgable

  def perform
    TechnicalIncidentEvaluation.where('created_at < ?', 180.days.ago).in_batches do |batch|
      # A single SQL update is intentional: callbacks must not run while purging retained PII at scale.
      # rubocop:disable Rails/SkipsModelValidations
      batch.update_all(
        classification: {},
        candidate_snapshot: [],
        sanitized_contracts: [],
        selected_contract: {},
        source_message_id: nil,
        feedback_note: nil,
        updated_at: Time.current
      )
      # rubocop:enable Rails/SkipsModelValidations
    end
    TechnicalIncidentUpdate.where('created_at < ?', 5.years.ago).in_batches.delete_all
  end
end
