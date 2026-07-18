require 'rails_helper'

RSpec.describe TechnicalIncidents::Matcher do
  let(:account) { create(:account) }
  let(:contract) do
    {
      contract_id: 'CTR-100',
      status: 'active',
      pop_id: 'POP-10',
      pop_name: 'Olinda',
      service_group: 'Internet',
      connection_type: 'Fibra',
      location: {
        state: 'PE',
        city: 'Recife',
        neighborhood: 'Boa Viagem',
        postal_code: '50000-000',
        street: 'Rua Exemplo',
        number: '10'
      }
    }
  end

  def incident_for(type, values)
    incident = create(:technical_incident, :active, account: account)
    group = create(:technical_incident_scope_group, account: account, technical_incident: incident)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: type,
      values: values
    )
    incident
  end

  {
    'contract_id' => ['CTR-100'],
    'pop_id' => ['POP-10'],
    'postal_code' => ['50000000'],
    'city_neighborhood' => [{ city: 'Récife', neighborhood: 'Boa-Viagem' }],
    'city_street' => [{ city: 'Recife', street: 'Rua Exemplo' }]
  }.each do |type, values|
    it "matches #{type} deterministically" do
      match = described_class.new(incident: incident_for(type, values), contract: contract).call

      expect(match[:match_source]).to eq(type)
    end
  end

  it 'never substitutes pop_name for the postal city' do
    incident = incident_for('city_neighborhood', [{ city: 'Olinda', neighborhood: 'Boa Viagem' }])

    expect(described_class.new(incident: incident, contract: contract).call).to be_nil
  end

  it 'does not match an inactive contract' do
    incident = incident_for('contract_id', ['CTR-100'])

    expect(described_class.new(incident: incident, contract: contract.merge(status: 'inactive')).call).to be_nil
  end

  it 'allows a contract without location to match only exact technical identifiers' do
    exact = incident_for('contract_id', ['CTR-100'])
    postal = incident_for('postal_code', ['50000000'])
    locationless = contract.merge(location: {})

    expect(described_class.new(incident: exact, contract: locationless).call).to be_present
    expect(described_class.new(incident: postal, contract: locationless).call).to be_nil
  end

  it 'matches a service criterion against the semantic service instead of contract display fields' do
    incident = incident_for('service_specific', ['google'])

    match = described_class.new(
      incident: incident,
      contract: contract,
      classification: { service_key: 'google' }
    ).call
    mismatch = described_class.new(
      incident: incident,
      contract: contract,
      classification: { service_key: 'youtube' }
    ).call

    expect(match[:match_source]).to eq('service_specific')
    expect(mismatch).to be_nil
  end
end
