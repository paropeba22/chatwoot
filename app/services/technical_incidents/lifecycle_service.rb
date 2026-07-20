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
    attributes = attributes.to_h.symbolize_keys

    @incident.with_lock do
      @incident.reload
      validate_actor!
      raise InvalidTransition, 'feature_disabled' unless @incident.account.feature_enabled?('technical_incidents')
      expected_lock_version = attributes.delete(:lock_version)
      if expected_lock_version.present? && expected_lock_version.to_i != @incident.lock_version
        raise ActiveRecord::StaleObjectError.new(@incident, 'transition')
      end

      previous_status = @incident.status
      raise InvalidTransition, target_status unless TRANSITIONS.fetch(previous_status, []).include?(target_status)
      if reopening?(previous_status, target_status) && attributes[:expires_at].blank?
        raise InvalidTransition, 'reopening_requires_new_expiration'
      end

      assign_transition_attributes(previous_status, target_status, attributes)
      TechnicalIncidents::IncidentValidator.new(@incident).validate!
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

  def assign_transition_attributes(previous_status, target_status, attributes)
    @incident.status = target_status
    @incident.updated_by = @actor if @actor.is_a?(User)

    if target_status == 'active'
      is_reopening = reopening?(previous_status, target_status)
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
    elsif target_status == 'scheduled'
      @incident.expires_at = attributes[:expires_at].presence || (@incident.starts_at && @incident.starts_at + 6.hours)
    end

    @incident.assign_attributes(attributes.slice(:expires_at, :review_at, :estimated_resolution_at))
  end

  def validate_actor!
    return unless @actor.is_a?(User)
    return if @incident.account.account_users.exists?(user_id: @actor.id)

    raise InvalidTransition, 'actor_account_mismatch'
  end

  def reopening?(previous_status, target_status)
    target_status == 'active' && %w[resolved expired cancelled].include?(previous_status)
  end
end
