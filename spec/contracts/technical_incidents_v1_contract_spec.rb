require 'rails_helper'

module TechnicalIncidentsV1Contract; end

RSpec.describe TechnicalIncidentsV1Contract do
  let(:fixtures_path) { Rails.root.join('spec/fixtures/technical_incidents/v1') }

  def fixture(name)
    JSON.parse(fixtures_path.join("#{name}.json").read)
  end

  it 'keeps the precheck classifier payload free of customer and network identity data' do
    payload = fixture('precheck_request')
    serialized = payload.to_json.downcase

    expect(payload.keys).to contain_exactly(
      'conversation_display_id',
      'source_message_id',
      'mode',
      'request_id',
      'contract_version',
      'classification'
    )
    expect(serialized).not_to match(/cpf|cnpj|phone|telefone|address|endereco|contract_id|pop_id/)
  end

  it 'accepts only the proven V1 sanitized contract fields' do
    contract = fixture('match_request').fetch('contracts').first
    allowed = TechnicalIncidents::MatchService::ALLOWED_CONTRACT_KEYS

    expect(contract.keys - allowed).to be_empty
    expect(contract.fetch('location').keys).to contain_exactly(
      'state', 'city', 'neighborhood', 'postal_code', 'street', 'number'
    )
    expect(contract.to_json.downcase).not_to match(/cpf|senha|password|login|mac|quitacao|referencia/)
  end

  it 'keeps commit body empty because the opaque path identifier is authoritative' do
    expect(fixture('commit_request')).to eq({})
  end

  it 'uses only a controlled feedback enum' do
    expect(TechnicalIncidentEvaluation::FEEDBACK_TYPES).to include(fixture('feedback_request').fetch('feedback'))
  end

  it 'exposes every status required by the AntiGravity V1 adapters' do
    expect(TechnicalIncidentEvaluation::STATUSES).to include(
      'no_candidate',
      'general_match',
      'localized_candidate',
      'needs_document',
      'needs_contract_selection',
      'matched',
      'ambiguous',
      'expired',
      'fallback',
      'duplicate',
      'accepted',
      'stale'
    )
  end

  it 'pins the live workflow metadata while requiring a redacted Code verification before production' do
    source = fixture('antigravity_source')

    expect(source).to include(
      'workflow_id' => '8k30Q8FFwvr3lbtu',
      'draft_version_id' => '4b2c8033-1c6f-485f-8770-4ceea73fe0e6',
      'published_version_id' => '8d433990-e41f-471b-bf32-b8aaed588db7',
      'canonical_no_match_status' => 'no_candidate',
      'code_verification' => 'pending_redacted_export'
    )
    expect(source.fetch('nodes')).to contain_exactly(
      'TI_API_Contract_V1',
      'TI_Precheck_Adapter_V1',
      'TI_Match_Adapter_V1',
      'TI_Commit_Adapter_V1',
      'TI_Feedback_Adapter_V1'
    )
    expect(TechnicalIncidentEvaluation::STATUSES).not_to include('no_match')
  end
end
