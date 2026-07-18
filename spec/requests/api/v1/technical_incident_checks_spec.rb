require 'rails_helper'

RSpec.describe 'Technical incident automation V1', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:other_account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:agent_bot) { create(:agent_bot, account: account, bot_config: { technical_incidents_api: true }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:headers) { { api_access_token: agent_bot.access_token.token } }
  let(:precheck_payload) do
    {
      conversation_display_id: conversation.display_id,
      source_message_id: 'source-contract-1',
      mode: 'shadow',
      request_id: 'request-contract-1',
      contract_version: '1.0',
      classification: {
        is_support_issue: true,
        problem_type: 'total_outage',
        service_key: 'internet',
        symptoms: ['sem conexão'],
        semantic_confidence: 0.95,
        topic_change: false,
        needs_clarification: false,
        reason_code: 'internet_outage'
      }
    }
  end

  before do
    incident = create(:technical_incident, :active, account: account)
    group = create(:technical_incident_scope_group, account: account, technical_incident: incident)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: 'general',
      values: []
    )
  end

  it 'accepts the V1 precheck fixture and returns only a backend-generated opaque identifier' do
    post '/api/v1/technical_incident_checks/precheck',
         params: precheck_payload,
         headers: headers,
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'contract_version' => '1.0',
      'status' => 'general_match'
    )
    expect(response.parsed_body.values_at('id', 'check_id', 'evaluation_id', 'commit_token').uniq.one?).to be(true)
  end

  it 'rejects invalid tokens and user tokens outside the AgentBot allowlist' do
    post '/api/v1/technical_incident_checks/precheck',
         params: precheck_payload,
         headers: { api_access_token: 'invalid' },
         as: :json
    expect(response).to have_http_status(:unauthorized)

    user = create(:user, account: account)
    post '/api/v1/technical_incident_checks/precheck',
         params: precheck_payload.merge(request_id: 'user-request'),
         headers: { api_access_token: user.access_token.token },
         as: :json
    expect(response).to have_http_status(:unauthorized)

    regular_bot = create(:agent_bot, account: account)
    post '/api/v1/technical_incident_checks/precheck',
         params: precheck_payload.merge(request_id: 'regular-bot-request'),
         headers: { api_access_token: regular_bot.access_token.token },
         as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'derives the account from the token and cannot access another account conversation' do
    foreign_conversation = create(:conversation, account: other_account)
    post '/api/v1/technical_incident_checks/precheck',
         params: precheck_payload.merge(
           account_id: other_account.id,
           conversation_display_id: foreign_conversation.display_id
         ),
         headers: headers,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include(
      'status' => 'fallback',
      'reason_code' => 'unexpected_precheck_field'
    )
    expect(other_account.technical_incident_evaluations).to be_empty
  end

  it 'does not write when the feature is disabled' do
    account.disable_features!('technical_incidents')

    expect do
      post '/api/v1/technical_incident_checks/precheck',
           params: precheck_payload,
           headers: headers,
           as: :json
    end.not_to change(TechnicalIncidentEvaluation, :count)

    expect(response.parsed_body).to include(
      'status' => 'fallback',
      'reason_code' => 'feature_disabled'
    )
  end

  it 'rejects extra fields in match, commit and feedback payloads before resolving an opaque ID' do
    post '/api/v1/technical_incident_checks/opaque/match',
         params: { contracts: [{ contract_id: 'CTR-1', cpf: 'not-accepted' }] },
         headers: headers,
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['reason_code']).to eq('contract_contains_forbidden_fields')

    post '/api/v1/technical_incident_checks/opaque/commit',
         params: { incident_id: 1 },
         headers: headers,
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['reason_code']).to eq('unexpected_commit_field')

    post '/api/v1/technical_incident_evaluations/opaque/feedback',
         params: { feedback: 'correct_match', cpf: 'not-accepted' },
         headers: headers,
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['reason_code']).to eq('unexpected_feedback_field')
  end
end
