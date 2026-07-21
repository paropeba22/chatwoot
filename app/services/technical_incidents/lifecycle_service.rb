class TechnicalIncidents::LifecycleService
  class InvalidTransition < StandardError; end

  TRANSITIONS = {
    'draft' => %w[scheduled active cancelled],
    'scheduled' => %w[active cancelled expired],
    'active' => %w[monitoring resolved expired cancelled],
    'monitoring' => %w[active resolved expired cancelled],
    'resolved' => %w[active],
    'expired' => %w[active],
    'cancelled' => %w[active]
  }.freeze

  def initialize(incident:, actor:, origin: 'ui', request_id: nil)
    @incident = incident
    @actor = actor
    @origin = origin
    @request_id = request_id
  end

  def transition!(target_status, attributes = {})
    @target_status = target_status.to_s
    @attributes = attributes.to_h.symbolize_keys
    @incident.with_lock { transition_locked! }
    @incident
  end

  private

  def transition_locked!
    @incident.reload
    validator.validate!
    previous_status = @incident.status
    TechnicalIncidents::LifecycleAttributes.new(
      incident: @incident,
      actor: @actor,
      previous_status: previous_status,
      target_status: @target_status,
      attributes: @attributes
    ).assign!
    persist_transition!(previous_status)
  end

  def validator
    @validator ||= TechnicalIncidents::LifecycleValidator.new(
      incident: @incident,
      actor: @actor,
      target_status: @target_status,
      attributes: @attributes,
      transitions: TRANSITIONS
    )
  end

  def persist_transition!(previous_status)
    TechnicalIncidents::IncidentValidator.new(@incident).validate!
    @incident.save!
    TechnicalIncidents::AuditService.record!(
      incident: @incident,
      action: "transition.#{previous_status}.#{@target_status}",
      actor: @actor,
      origin: @origin,
      request_id: @request_id,
      changeset: @incident.previous_changes.except('updated_at', 'lock_version')
    )
  end
end
