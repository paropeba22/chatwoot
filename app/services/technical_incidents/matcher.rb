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
  CRITERION_MATCHERS = {
    'general' => :general?,
    'service_specific' => :service_specific?,
    'contract_id' => :contract_id?,
    'pop_id' => :pop_id?,
    'postal_code' => :postal_code?,
    'city_neighborhood' => :city_neighborhood?,
    'city_street' => :city_street?
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
    matcher = CRITERION_MATCHERS[criterion.criterion_type]
    matcher && public_send(matcher, criterion.values)
  end

  def general?(_values)
    true
  end

  def service_specific?(values)
    values.include?(@classification['service_key'])
  end

  def contract_id?(values)
    exact?(values, @contract['contract_id'])
  end

  def pop_id?(values)
    exact?(values, @contract['pop_id'])
  end

  def city_neighborhood?(values)
    pair?(values, 'neighborhood')
  end

  def city_street?(values)
    pair?(values, 'street')
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
