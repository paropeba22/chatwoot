class TechnicalIncidents::SemanticGate
  EXACT_MATCH_SOURCES = %w[contract_id pop_id].freeze
  HIGH_CONFIDENCE_MATCH_SOURCES = %w[postal_code city_neighborhood city_street service_specific general].freeze

  Result = Data.define(:allowed, :status, :reason_code, :confidence_level, :allowed_match_sources) do
    def allowed?
      allowed
    end
  end

  def self.call(classification)
    data = classification.to_h.stringify_keys
    denied_result = classification_denial(data)
    return denied_result if denied_result

    confidence = data['semantic_confidence']
    return denied('fallback', 'semantic_confidence_invalid') unless confidence.is_a?(Numeric)
    return denied('fallback', 'semantic_confidence_low') if confidence < TechnicalIncidents::Configuration.medium_confidence

    allowed_result(confidence)
  end

  def self.allowed_match_source?(classification, match_source)
    result = call(classification)
    result.allowed && result.allowed_match_sources.include?(match_source.to_s)
  end

  def self.valid_shape?(data)
    data['is_support_issue'].in?([true, false]) &&
      data['topic_change'].in?([true, false]) &&
      data['needs_clarification'].in?([true, false]) &&
      TechnicalIncident::PROBLEM_TYPES.include?(data['problem_type']) &&
      (data['service_key'].blank? || TechnicalIncident::SERVICE_KEYS.include?(data['service_key']))
  end

  def self.classification_denial(data)
    return denied('fallback', 'classification_invalid') unless valid_shape?(data)
    return denied('fallback', 'topic_changed') if data['topic_change']
    return denied('fallback', 'needs_clarification') if data['needs_clarification']
    return denied('no_candidate', 'not_support_issue') unless data['is_support_issue']
  end

  def self.allowed_result(confidence)
    high = confidence >= TechnicalIncidents::Configuration.high_confidence
    Result.new(
      allowed: true,
      status: nil,
      reason_code: high ? 'semantic_confidence_high' : 'semantic_confidence_medium',
      confidence_level: high ? 'high' : 'medium',
      allowed_match_sources: high ? EXACT_MATCH_SOURCES + HIGH_CONFIDENCE_MATCH_SOURCES : EXACT_MATCH_SOURCES
    )
  end

  def self.denied(status, reason_code)
    Result.new(allowed: false, status: status, reason_code: reason_code, confidence_level: 'invalid', allowed_match_sources: [])
  end

  private_class_method :classification_denial, :allowed_result, :denied
end
