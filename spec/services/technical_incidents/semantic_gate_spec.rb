require 'rails_helper'

RSpec.describe TechnicalIncidents::SemanticGate do
  subject(:result) { described_class.call(classification) }

  let(:classification) do
    {
      is_support_issue: true,
      problem_type: 'internet_connectivity',
      service_key: 'internet',
      semantic_confidence: 0.95,
      topic_change: false,
      needs_clarification: false
    }
  end

  it 'rejects zero confidence, topic changes, clarification and incomplete classifications' do
    [
      classification.merge(semantic_confidence: 0),
      classification.merge(topic_change: true),
      classification.merge(needs_clarification: true),
      classification.except(:problem_type),
      classification.merge(semantic_confidence: nil)
    ].each do |adversarial|
      expect(described_class.call(adversarial)).not_to be_allowed
    end
  end

  it 'permits only exact contract and pop matches at medium confidence' do
    medium = described_class.call(classification.merge(semantic_confidence: 0.75))

    expect(medium).to be_allowed
    expect(medium.allowed_match_sources).to contain_exactly('contract_id', 'pop_id')
  end

  it 'requires high confidence for address, service-specific and general matches' do
    expect(result.allowed_match_sources).to include(
      'postal_code', 'city_neighborhood', 'city_street', 'service_specific', 'general'
    )
  end

  it 'rejects unknown problem types and incompatible service keys' do
    expect(described_class.call(classification.merge(problem_type: 'invented'))).not_to be_allowed
    expect(described_class.call(classification.merge(service_key: 'invented'))).not_to be_allowed
  end
end
