class TechnicalIncidents::IncidentValidator
  OPERATIONAL_STATUSES = %w[scheduled active monitoring].freeze

  def initialize(incident)
    @incident = incident
  end

  def validate!
    @incident.validate
    validate_operational_invariants if OPERATIONAL_STATUSES.include?(@incident.status)
    raise ActiveRecord::RecordInvalid, @incident if @incident.errors.any?

    true
  end

  private

  def validate_operational_invariants
    add_error(:expires_at, :blank) if @incident.expires_at.blank?
    validate_window
    validate_scope
    validate_template
  end

  def validate_window
    return if @incident.expires_at.blank?

    validate_current_window
    validate_scheduled_window
    validate_maximum_window
  end

  def validate_current_window
    operational = %w[active monitoring].include?(@incident.status)
    add_error(:expires_at, :expired) if operational && @incident.expires_at <= Time.current

    future_start = @incident.starts_at.present? && @incident.starts_at > Time.current
    add_error(:starts_at, :not_started) if @incident.status == 'active' && future_start
  end

  def validate_scheduled_window
    return unless @incident.status == 'scheduled'

    add_error(:starts_at, :blank) if @incident.starts_at.blank?
    add_error(:starts_at, :not_future) if @incident.starts_at.present? && @incident.starts_at <= Time.current
  end

  def validate_maximum_window
    base_time = @incident.starts_at || Time.current
    add_error(:expires_at, :too_far) if @incident.expires_at > base_time + 7.days
  end

  def validate_scope
    groups = @incident.scope_groups.reject(&:marked_for_destruction?)
    add_error(:scope_groups, :blank) if groups.empty?
    add_error(:scope_groups, :invalid) if groups.any? { |group| group.criteria.reject(&:marked_for_destruction?).empty? }
  end

  def validate_template
    if @incident.action != 'handoff_only' && @incident.customer_message.blank?
      add_error(:customer_message, :blank)
      return
    end

    TechnicalIncidents::TemplateRenderer.validate!(@incident) unless @incident.action == 'handoff_only'
  rescue TechnicalIncidents::TemplateRenderer::InvalidTemplate => e
    add_error(:customer_message, e.message)
  end

  def add_error(attribute, message)
    @incident.errors.add(attribute, message) unless @incident.errors.added?(attribute, message)
  end
end
