require 'rails_helper'

RSpec.describe TechnicalIncidents::PrecheckService do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:agent_bot) { create(:agent_bot, account: account, bot_config: { technical_incidents_api: true }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:classification) do
    {
      is_support_issue: true,
      problem_type: 'total_outage',
      service_key: 'internet',
      symptoms: ['sem internet'],
      semantic_confidence: 0.96,
      topic_change: false,
      needs_clarification: false,
      reason_code: 'internet_outage'
    }
  end

  def create_incident(status: 'active', scope_type: 'general', values: [])
    incident = create(:technical_incident, account: account, status: status)
    group = create(:technical_incident_scope_group, account: account, technical_incident: incident)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: scope_type,
      values: values
    )
    incident
  end

  def payload(overrides = {})
    {
      conversation_display_id: conversation.display_id,
      source_message_id: 'message-100',
      mode: 'shadow',
      classification: classification,
      request_id: 'request-100',
      contract_version: '1.0'
    }.deep_merge(overrides)
  end

  it 'returns a general match using the V1 opaque aliases' do
    incident = create_incident

    result = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call

    expect(result[:status]).to eq('general_match')
    expect(result.values_at(:id, :check_id, :evaluation_id, :commit_token).uniq.one?).to be(true)
    expect(result.dig(:incident, :id)).to eq(incident.id)
  end

  it 'returns a localized candidate without asking for document or selecting a contract' do
    create_incident(scope_type: 'pop_id', values: ['POP-10'])

    result = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call

    expect(result[:status]).to eq('localized_candidate')
    expect(conversation.reload.messages).to be_empty
  end

  it 'defers a broad general incident when a localized candidate may be more specific' do
    create_incident
    localized = create_incident(scope_type: 'pop_id', values: ['POP-10'])

    result = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call

    expect(result[:status]).to eq('localized_candidate')
    expect(result.dig(:incident, :id)).to eq(localized.id)
  end

  it 'returns duplicate for the same request or source message' do
    create_incident
    first = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call
    duplicate = described_class.new(
      account: account,
      agent_bot: agent_bot,
      payload: payload(request_id: 'request-101')
    ).call

    expect(first[:status]).to eq('general_match')
    expect(duplicate[:status]).to eq('duplicate')
    expect(duplicate[:evaluation_id]).to eq(first[:evaluation_id])
  end

  it 'returns fallback for monitoring and expired for expired incidents' do
    create_incident(status: 'monitoring')
    monitoring = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call
    expect(monitoring[:status]).to eq('fallback')

    TechnicalIncident.delete_all
    create_incident(status: 'expired')
    expired = described_class.new(
      account: account,
      agent_bot: agent_bot,
      payload: payload(request_id: 'request-expired', source_message_id: 'message-expired')
    ).call
    expect(expired[:status]).to eq('expired')
  end

  it 'fails closed when the feature is disabled' do
    account.disable_features!('technical_incidents')

    result = described_class.new(account: account, agent_bot: agent_bot, payload: payload).call

    expect(result).to include(status: 'fallback', reason_code: 'feature_disabled')
    expect(account.technical_incident_evaluations).to be_empty
  end
end
