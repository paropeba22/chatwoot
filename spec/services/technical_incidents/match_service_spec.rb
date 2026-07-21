require 'rails_helper'

RSpec.describe TechnicalIncidents::MatchService do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:conversation) { create(:conversation, account: account) }
  let(:incident) do
    record = create(:technical_incident, :active, account: account)
    group = create(:technical_incident_scope_group, account: account, technical_incident: record)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: 'pop_id',
      values: ['POP-10']
    )
    record
  end
  let(:evaluation) do
    create(
      :technical_incident_evaluation,
      account: account,
      conversation: conversation,
      technical_incident: incident,
      status: 'localized_candidate',
      classification: {
        is_support_issue: true,
        problem_type: 'internet_connectivity',
        service_key: 'internet',
        semantic_confidence: 0.95,
        topic_change: false,
        needs_clarification: false
      },
      candidate_snapshot: [incident.customer_visible_snapshot]
    )
  end
  let(:contract) do
    {
      contract_id: 'CTR-100',
      status: 'active',
      pop_id: 'POP-10',
      pop_name: 'Olinda',
      service_group: 'Internet',
      connection_type: 'Fibra',
      state: 'PE',
      city: 'Recife',
      neighborhood: 'Boa Viagem',
      postal_code: '50000-000',
      street: 'Rua Exemplo',
      number: '10'
    }
  end

  around do |example|
    with_modified_env TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'shadow' do
      example.run
    end
  end

  it 'matches a single sanitized contract and persists no forbidden fields' do
    result = described_class.new(account: account, evaluation: evaluation, payload: { contracts: [contract] }).call

    expect(result).to include(status: 'matched', match_source: 'pop_id')
    expect(evaluation.reload.selected_contract).to include('contract_id' => 'CTR-100', 'pop_name' => 'Olinda')
    expect(evaluation.selected_contract.to_json).not_to include('cpf', 'password', 'mac')
  end

  it 'returns the persisted result on a retry after a successful match' do
    first = described_class.new(account: account, evaluation: evaluation, payload: { contracts: [contract] }).call
    retry_result = described_class.new(account: account, evaluation: evaluation.reload, payload: { contracts: [contract] }).call

    expect(first[:status]).to eq('matched')
    expect(retry_result).to include(status: 'matched', match_source: 'pop_id')
  end

  it 'requires explicit selection for multiple contracts' do
    result = described_class.new(
      account: account,
      evaluation: evaluation,
      payload: { contracts: [contract, contract.merge(contract_id: 'CTR-200')] }
    ).call

    expect(result).to include(
      status: 'needs_contract_selection',
      reason_code: 'multiple_contracts_require_selection'
    )
  end

  it 'rejects forbidden personal or credential fields' do
    result = described_class.new(
      account: account,
      evaluation: evaluation,
      payload: { contracts: [contract.merge(cpf: '00000000000', password: 'secret')] }
    ).call

    expect(result).to include(status: 'fallback', reason_code: 'contract_contains_forbidden_fields')
    expect(evaluation.reload.sanitized_contracts).to be_empty
  end

  it 'returns no candidate for an inactive contract' do
    result = described_class.new(
      account: account,
      evaluation: evaluation,
      payload: { contracts: [contract.merge(status: 'inactive')] }
    ).call

    expect(result[:status]).to eq('no_candidate')
  end
end
