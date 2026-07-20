class TechnicalIncidents::LifecycleValidator
  def initialize(incident:, actor:, target_status:, attributes:, transitions:)
    @incident = incident
    @actor = actor
    @target_status = target_status
    @attributes = attributes
    @transitions = transitions
  end

  def validate!
    validate_actor!
    reject!('feature_disabled') unless @incident.account.feature_enabled?('technical_incidents')
    validate_lock_version!
    validate_transition!
    validate_reopening!
  end

  private

  def validate_actor!
    return unless @actor.is_a?(User)

    reject!('actor_account_mismatch') unless @incident.account.account_users.exists?(user_id: @actor.id)
  end

  def validate_lock_version!
    expected = @attributes.delete(:lock_version)
    return if expected.blank? || expected.to_i == @incident.lock_version

    raise ActiveRecord::StaleObjectError.new(@incident, 'transition')
  end

  def validate_transition!
    allowed = @transitions.fetch(@incident.status, []).include?(@target_status)
    reject!(@target_status) unless allowed
  end

  def validate_reopening!
    return unless reopening?

    reject!('reopening_requires_new_expiration') if @attributes[:expires_at].blank?
  end

  def reopening?
    @target_status == 'active' && %w[resolved expired cancelled].include?(@incident.status)
  end

  def reject!(reason_code)
    raise TechnicalIncidents::LifecycleService::InvalidTransition, reason_code
  end
end
