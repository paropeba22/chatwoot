class TechnicalIncidents::FeedbackService
  def initialize(evaluation:, feedback:, note:, actor:)
    @evaluation = evaluation
    @feedback = feedback
    @note = note
    @actor = actor
  end

  def call
    @evaluation.update!(
      feedback: @feedback,
      feedback_note: TechnicalIncidents::TextSanitizer.call(@note)&.first(1_000),
      feedback_by: @actor.is_a?(User) ? @actor : nil
    )
    if @evaluation.technical_incident
      TechnicalIncidents::AuditService.record!(
        incident: @evaluation.technical_incident,
        action: "feedback.#{@feedback}",
        actor: @actor,
        origin: @actor.is_a?(AgentBot) ? 'automation' : 'ui',
        request_id: @evaluation.request_id,
        changeset: { evaluation_id: @evaluation.id }
      )
    end
    @evaluation
  end
end
