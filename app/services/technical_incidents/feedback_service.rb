class TechnicalIncidents::FeedbackService
  def initialize(evaluation:, feedback:, note:, actor:)
    @evaluation = evaluation
    @feedback = feedback
    @note = note
    @actor = actor
  end

  def call
    @evaluation.with_lock { persist_feedback }
    @evaluation
  end

  private

  def actor_authorized?
    if @actor.is_a?(AgentBot)
      return @actor.account_id == @evaluation.account_id && @actor.bot_config.to_h['technical_incidents_api'] == true
    end
    return @evaluation.account.account_users.exists?(user_id: @actor.id) if @actor.is_a?(User)

    false
  end

  def persist_feedback
    @evaluation.reload
    validate_authorization!
    @evaluation.update!(feedback_attributes)
    record_audit
    record_instrumentation
  end

  def validate_authorization!
    raise ActiveRecord::RecordInvalid, @evaluation unless @evaluation.account.feature_enabled?('technical_incidents')
    raise Pundit::NotAuthorizedError unless actor_authorized?
  end

  def feedback_attributes
    {
      feedback: @feedback,
      feedback_note: TechnicalIncidents::TextSanitizer.call(@note)&.first(1_000),
      feedback_by: @actor.is_a?(User) ? @actor : nil
    }
  end

  def record_audit
    return unless @evaluation.technical_incident

    TechnicalIncidents::AuditService.record!(
      incident: @evaluation.technical_incident,
      action: "feedback.#{@feedback}",
      origin: @actor.is_a?(AgentBot) ? 'automation' : 'ui',
      actor: @actor,
      request_id: @evaluation.request_id,
      changeset: { evaluation_id: @evaluation.id }
    )
  end

  def record_instrumentation
    TechnicalIncidents::Instrumentation.record(
      event: 'feedback',
      request_id: @evaluation.request_id,
      evaluation_id: @evaluation.opaque_id,
      incident_id: @evaluation.technical_incident_id,
      conversation_id: @evaluation.conversation_id,
      status: @feedback
    )
  end
end
