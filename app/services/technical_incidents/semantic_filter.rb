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
      normalize_taxonomy(classification)
      normalize_symptoms(classification)
      normalize_gates(classification)
    end
  end

  def self.compatible?(incident, classification)
    valid_problem?(incident, classification) &&
      compatible_affected_service?(incident, classification['service_key']) &&
      compatible_scope_service?(incident, classification['service_key'])
  end

  def self.strict_confidence(value)
    return unless value.is_a?(Numeric) || value.to_s.match?(/\A(?:0(?:\.\d+)?|1(?:\.0+)?)\z/)

    Float(value).clamp(0.0, 1.0)
  rescue ArgumentError, TypeError
    nil
  end

  def self.normalize_taxonomy(classification)
    problem_type = classification['problem_type'].to_s
    classification['problem_type'] = PROBLEM_TYPE_ALIASES.fetch(problem_type, problem_type)
    classification['service_key'] = classification['service_key'].to_s
  end

  def self.normalize_symptoms(classification)
    classification['symptoms'] = Array(classification['symptoms']).first(10).map do |value|
      TechnicalIncidents::Normalizer.text(value)[0, 100]
    end
  end

  def self.normalize_gates(classification)
    classification['semantic_confidence'] = strict_confidence(classification['semantic_confidence'])
    classification['topic_change'] = strict_boolean(classification['topic_change'])
    classification['needs_clarification'] = strict_boolean(classification['needs_clarification'])
  end

  def self.strict_boolean(value)
    value if value.in?([true, false])
  end

  def self.valid_problem?(incident, classification)
    TechnicalIncidents::SemanticGate.call(classification).allowed &&
      classification['is_support_issue'] == true &&
      TechnicalIncident::PROBLEM_TYPES.include?(classification['problem_type']) &&
      incident.problem_types.include?(classification['problem_type'])
  end

  def self.compatible_affected_service?(incident, service_key)
    incident.affected_services.empty? ||
      (TechnicalIncident::SERVICE_KEYS.include?(service_key) && incident.affected_services.include?(service_key))
  end

  def self.compatible_scope_service?(incident, service_key)
    incident.scope_groups.any? do |group|
      criteria = group.criteria.select(&:service_specific?)
      criteria.empty? || criteria.any? { |criterion| criterion.values.include?(service_key) }
    end
  end

  private_class_method :strict_confidence, :normalize_taxonomy, :normalize_symptoms, :normalize_gates, :strict_boolean,
                       :valid_problem?, :compatible_affected_service?, :compatible_scope_service?
end
