class TechnicalIncidents::SemanticFilter
  PROBLEM_TYPE_ALIASES = {
    'total_outage' => 'internet_connectivity',
    'slow_connection' => 'internet_connectivity',
    'instability' => 'internet_connectivity',
    'red_light' => 'optical_alarm',
    'fiber_break' => 'physical_fiber',
    'app_unavailable' => 'company_application'
  }.freeze
  ALLOWED_CLASSIFICATION_KEYS = %w[
    is_support_issue problem_type service_key symptoms semantic_confidence topic_change needs_clarification reason_code
  ].freeze

  def self.sanitize(raw)
    raw.to_h.stringify_keys.slice(*ALLOWED_CLASSIFICATION_KEYS).tap do |classification|
      classification['problem_type'] = PROBLEM_TYPE_ALIASES.fetch(
        classification['problem_type'].to_s,
        classification['problem_type'].to_s
      )
      classification['service_key'] = classification['service_key'].to_s
      classification['symptoms'] = Array(classification['symptoms']).first(10).map { |value| TechnicalIncidents::Normalizer.text(value)[0, 100] }
      classification['semantic_confidence'] = strict_confidence(classification['semantic_confidence'])
      classification['topic_change'] = classification['topic_change'] if classification['topic_change'].in?([true, false])
      classification['needs_clarification'] = classification['needs_clarification'] if classification['needs_clarification'].in?([true, false])
    end
  end

  def self.compatible?(incident, classification)
    return false unless TechnicalIncidents::SemanticGate.call(classification).allowed
    return false unless classification['is_support_issue'] == true
    return false unless TechnicalIncident::PROBLEM_TYPES.include?(classification['problem_type'])
    return false unless incident.problem_types.include?(classification['problem_type'])

    service_key = classification['service_key']
    affected_service_compatible = incident.affected_services.empty? ||
                                  (TechnicalIncident::SERVICE_KEYS.include?(service_key) &&
                                   incident.affected_services.include?(service_key))
    return false unless affected_service_compatible

    incident.scope_groups.any? do |group|
      service_criteria = group.criteria.select(&:service_specific?)
      service_criteria.empty? || service_criteria.any? { |criterion| criterion.values.include?(service_key) }
    end
  end

  def self.strict_confidence(value)
    return unless value.is_a?(Numeric) || value.to_s.match?(/\A(?:0(?:\.\d+)?|1(?:\.0+)?)\z/)

    Float(value).clamp(0.0, 1.0)
  rescue ArgumentError, TypeError
    nil
  end

  private_class_method :strict_confidence
end
