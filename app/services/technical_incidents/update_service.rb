class TechnicalIncidents::UpdateService
  def initialize(incident:, attributes:, actor:)
    @incident = incident
    @attributes = attributes
    @actor = actor
  end

  def call
    @incident.with_lock { update_locked! }
    @incident
  end

  private

  def versioned_change?(previous_fingerprint)
    return false unless %w[active monitoring].include?(@incident.status)

    previous_fingerprint != notification_fingerprint
  end

  def notification_fingerprint
    {
      customer_message: @incident.customer_message,
      estimated_resolution_at: @incident.estimated_resolution_at,
      problem_types: Array(@incident.problem_types).sort,
      affected_services: Array(@incident.affected_services).sort,
      action: @incident.action,
      starts_at: @incident.starts_at,
      expires_at: @incident.expires_at,
      scope_groups: scope_fingerprint
    }
  end

  def scope_fingerprint
    active_scope_groups.map { |group| criterion_fingerprints(group) }
  end

  def update_locked!
    @incident.reload
    validate_update!
    previous_fingerprint = notification_fingerprint
    assign_attributes
    @incident.notification_version += 1 if versioned_change?(previous_fingerprint)
    TechnicalIncidents::IncidentValidator.new(@incident).validate!
    @incident.save!
    record_audit
  end

  def validate_update!
    raise ActiveRecord::RecordInvalid, @incident unless @incident.account.feature_enabled?('technical_incidents')
    raise ActiveRecord::RecordInvalid, @incident unless actor_in_account?

    expected = @attributes.to_h[:lock_version] || @attributes.to_h['lock_version']
    raise ActiveRecord::StaleObjectError.new(@incident, 'update') if expected.present? && expected.to_i != @incident.lock_version
  end

  def actor_in_account?
    !@actor.is_a?(User) || @incident.account.account_users.exists?(user_id: @actor.id)
  end

  def assign_attributes
    @incident.assign_attributes(@attributes.to_h.except(:lock_version, 'lock_version'))
    @incident.updated_by = @actor
  end

  def record_audit
    TechnicalIncidents::AuditService.record!(
      incident: @incident,
      action: 'incident.updated',
      actor: @actor,
      origin: 'ui',
      changeset: @incident.previous_changes.except('updated_at', 'lock_version')
    )
  end

  def active_scope_groups
    @incident.scope_groups.reject(&:marked_for_destruction?).sort_by { |group| [group.position, group.id.to_i] }
  end

  def criterion_fingerprints(group)
    criteria = group.criteria.reject(&:marked_for_destruction?)
                    .sort_by { |criterion| [criterion.criterion_type, criterion.id.to_i] }
    criteria.map do |criterion|
      [criterion.criterion_type, criterion.operator, Array(criterion.values).map(&:to_json).sort]
    end
  end
end
