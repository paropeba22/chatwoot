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

    add_error(:expires_at, :expired) if %w[active monitoring].include?(@incident.status) && @incident.expires_at <= Time.current
    if @incident.status == 'active' && @incident.starts_at.present? && @incident.starts_at > Time.current
      add_error(:starts_at, :not_started)
    end
    if @incident.status == 'scheduled'
      add_error(:starts_at, :blank) if @incident.starts_at.blank?
      add_error(:starts_at, :not_future) if @incident.starts_at.present? && @incident.starts_at <= Time.current
    end
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
