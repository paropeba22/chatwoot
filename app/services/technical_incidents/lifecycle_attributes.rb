class TechnicalIncidents::LifecycleAttributes
  CLIENT_TIMES = %i[expires_at review_at estimated_resolution_at].freeze

  def initialize(incident:, actor:, previous_status:, target_status:, attributes:)
    @incident = incident
    @actor = actor
    @previous_status = previous_status
    @target_status = target_status
    @attributes = attributes
  end

  def assign!
    @incident.status = @target_status
    @incident.updated_by = @actor if @actor.is_a?(User)
    __send__("assign_#{@target_status}!") if respond_to?("assign_#{@target_status}!", true)
    @incident.assign_attributes(@attributes.slice(*CLIENT_TIMES))
  end

  private

  def assign_active!
    @incident.starts_at = Time.current if reopening?
    @incident.starts_at ||= Time.current
    @incident.expires_at = requested_expiration || @incident.expires_at || 6.hours.from_now(@incident.starts_at)
    @incident.notification_version += 1 if reopening?
    @incident.resolved_at = nil
    @incident.resolved_by = nil
  end

  def assign_resolved!
    @incident.resolved_at = Time.current
    @incident.resolved_by = @actor if @actor.is_a?(User)
  end

  def assign_scheduled!
    @incident.expires_at = requested_expiration || default_scheduled_expiration
  end

  def requested_expiration
    @attributes[:expires_at].presence
  end

  def default_scheduled_expiration
    @incident.starts_at && 6.hours.from_now(@incident.starts_at)
  end

  def reopening?
    @target_status == 'active' && %w[resolved expired cancelled].include?(@previous_status)
  end
end
