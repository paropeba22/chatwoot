class TechnicalIncidents::UpdateService
  def initialize(incident:, attributes:, actor:)
    @incident = incident
    @attributes = attributes
    @actor = actor
  end

  def call
    @incident.with_lock do
      previous_fingerprint = notification_fingerprint
      @incident.assign_attributes(@attributes)
      @incident.updated_by = @actor
      @incident.notification_version += 1 if versioned_change?(previous_fingerprint)
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
