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
    target_status = target_status.to_s
    raise InvalidTransition, target_status unless TRANSITIONS.fetch(@incident.status, []).include?(target_status)
    if reopening?(target_status) && attributes.to_h[:expires_at].blank? && attributes.to_h['expires_at'].blank?
      raise InvalidTransition, 'reopening_requires_new_expiration'
    end

    @incident.with_lock do
      previous_status = @incident.status
      assign_transition_attributes(target_status, attributes.to_h.symbolize_keys)
      validate_activation! if target_status == 'active'
      prepare_scheduled! if target_status == 'scheduled'
      @incident.save!
      TechnicalIncidents::AuditService.record!(
        incident: @incident,
        action: "transition.#{previous_status}.#{target_status}",
        actor: @actor,
        origin: @origin,
        request_id: @request_id,
        changeset: @incident.previous_changes.except('updated_at', 'lock_version')
      )
    end
    @incident
  end

  private

  def assign_transition_attributes(target_status, attributes)
    @incident.status = target_status
    @incident.updated_by = @actor if @actor.is_a?(User)

    if target_status == 'active'
      is_reopening = %w[resolved expired cancelled].include?(@incident.status_was) || @incident.resolved_at.present?
      @incident.starts_at = Time.current if is_reopening
      @incident.starts_at ||= Time.current
      @incident.expires_at = attributes[:expires_at].presence || @incident.expires_at || (@incident.starts_at + 6.hours)
      if is_reopening
        @incident.notification_version += 1
      end
      @incident.resolved_at = nil
      @incident.resolved_by = nil
    elsif target_status == 'resolved'
      @incident.resolved_at = Time.current
      @incident.resolved_by = @actor if @actor.is_a?(User)
    end

    @incident.assign_attributes(attributes.slice(:expires_at, :review_at, :estimated_resolution_at))
  end

  def validate_activation!
    raise InvalidTransition, 'incident_not_started' if @incident.starts_at.present? && @incident.starts_at > Time.current
    raise InvalidTransition, 'customer_message_required' if @incident.action != 'handoff_only' && @incident.customer_message.blank?
    raise InvalidTransition, 'scope_required' if @incident.scope_groups.empty?

    TechnicalIncidents::TemplateRenderer.validate!(@incident)
    @incident.validate!
  end

  def prepare_scheduled!
    raise InvalidTransition, 'scheduled_start_required' if @incident.starts_at.blank?
    raise InvalidTransition, 'scheduled_start_must_be_future' if @incident.starts_at <= Time.current

    @incident.expires_at ||= @incident.starts_at + 6.hours
    @incident.validate!
  end

  def reopening?(target_status)
    target_status == 'active' && %w[resolved expired cancelled].include?(@incident.status)
  end
end
