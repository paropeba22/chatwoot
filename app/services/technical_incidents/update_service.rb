class TechnicalIncidents::UpdateService
  def initialize(incident:, attributes:, actor:)
    @incident = incident
    @attributes = attributes
    @actor = actor
  end

  def call
    @incident.with_lock do
      @incident.reload
      raise ActiveRecord::RecordInvalid, @incident unless @incident.account.feature_enabled?('technical_incidents')
      if @actor.is_a?(User) && !@incident.account.account_users.exists?(user_id: @actor.id)
        raise ActiveRecord::RecordInvalid, @incident
      end

      expected_lock_version = @attributes.to_h[:lock_version] || @attributes.to_h['lock_version']
      if expected_lock_version.present? && expected_lock_version.to_i != @incident.lock_version
        raise ActiveRecord::StaleObjectError.new(@incident, 'update')
      end

      previous_fingerprint = notification_fingerprint
      @incident.assign_attributes(@attributes.to_h.except(:lock_version, 'lock_version'))
      @incident.updated_by = @actor
      @incident.notification_version += 1 if versioned_change?(previous_fingerprint)
      TechnicalIncidents::IncidentValidator.new(@incident).validate!
      @incident.save!
      TechnicalIncidents::AuditService.record!(
        incident: @incident,
        action: 'incident.updated',
        actor: @actor,
        origin: 'ui',
        changeset: @incident.previous_changes.except('updated_at', 'lock_version')
      )
    end
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
    groups = @incident.scope_groups.reject(&:marked_for_destruction?)
                      .sort_by { |group| [group.position, group.id.to_i] }
    groups.map do |group|
      criteria = group.criteria.reject(&:marked_for_destruction?)
                      .sort_by { |criterion| [criterion.criterion_type, criterion.id.to_i] }
      criteria.map do |criterion|
        [
          criterion.criterion_type,
          criterion.operator,
          Array(criterion.values).map(&:to_json).sort
        ]
      end
    end
  end
end
