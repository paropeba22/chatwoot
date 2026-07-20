class TechnicalIncidents::Matcher
  SPECIFICITY = {
    'contract_id' => 600,
    'pop_id' => 500,
    'postal_code' => 400,
    'city_neighborhood' => 300,
    'city_street' => 200,
    'service_specific' => 100,
    'general' => 0
  }.freeze

  def initialize(incident:, contract:, classification: {})
    @incident = incident
    @contract = TechnicalIncidents::Normalizer.contract(contract)
    @classification = classification.to_h.stringify_keys
  end

  def call
    return unless @contract['status'] == 'active'

    matches = @incident.scope_groups.filter_map { |group| match_group(group) }
    match = matches.max_by { |result| result[:specificity] }
    return unless match
    return unless TechnicalIncidents::SemanticGate.allowed_match_source?(@classification, match[:match_source])

    match
  end

  private

  def match_group(group)
    results = group.criteria.map { |criterion| match_criterion(criterion) }
    return if results.any?(&:nil?)

    results.max_by { |result| result[:specificity] }
  end

  def match_criterion(criterion)
    matched = criterion_matches?(criterion)
    return unless matched

    { match_source: criterion.criterion_type, specificity: SPECIFICITY.fetch(criterion.criterion_type) }
  end

  def criterion_matches?(criterion)
    case criterion.criterion_type
    when 'general' then true
    when 'service_specific' then criterion.values.include?(@classification['service_key'])
    when 'contract_id' then exact?(criterion.values, @contract['contract_id'])
    when 'pop_id' then exact?(criterion.values, @contract['pop_id'])
    when 'postal_code' then postal_code?(criterion.values)
    when 'city_neighborhood' then pair?(criterion.values, 'neighborhood')
    when 'city_street' then pair?(criterion.values, 'street')
    end
  end

  def postal_code?(values)
    normalized = values.map { |value| TechnicalIncidents::Normalizer.postal_code(value) }
    normalized.include?(@contract.dig('location', 'postal_code'))
  end

  def exact?(values, contract_value)
    contract_value.present? && values.map { |value| TechnicalIncidents::Normalizer.identifier(value) }.include?(contract_value)
  end

  def pair?(values, second_key)
    city = @contract.dig('location', 'city')
    second_value = @contract.dig('location', second_key)
    return false if city.blank? || second_value.blank?

    values.any? do |value|
      TechnicalIncidents::Normalizer.text(value['city']) == city &&
        TechnicalIncidents::Normalizer.text(value[second_key]) == second_value
    end
  end
end
