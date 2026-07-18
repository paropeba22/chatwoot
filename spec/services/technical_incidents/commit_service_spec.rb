require 'rails_helper'

RSpec.describe TechnicalIncidents::CommitService do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:agent_bot) { create(:agent_bot, account: account, bot_config: { technical_incidents_api: true }) }
  let(:conversation) { create(:conversation, account: account, assignee_agent_bot: agent_bot) }
  let(:incident) do
    record = create(:technical_incident, :active, account: account)
    group = create(:technical_incident_scope_group, account: account, technical_incident: record)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: 'general',
      values: []
    )
    record
  end
  let(:evaluation) do
    create(
      :technical_incident_evaluation,
      account: account,
      conversation: conversation,
      agent_bot: agent_bot,
      technical_incident: incident,
      mode: 'active',
      status: 'general_match',
      classification: {
        is_support_issue: true,
        problem_type: 'internet_connectivity',
        service_key: 'internet',
        semantic_confidence: 0.95
      },
      candidate_snapshot: [incident.customer_visible_snapshot]
    )
  end

  before do
    allow_any_instance_of(described_class).to receive(:create_customer_message!) do
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        sender: agent_bot,
        message_type: :outgoing,
        content: incident.customer_message
      )
    end
  end

  it 'revalidates and commits once using the backend-owned message and handoff' do
    result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call

    expect(result[:status]).to eq('accepted')
    expect(account.technical_incident_deliveries.count).to eq(1)
    expect(account.technical_incident_conversation_links.count).to eq(1)
    expect(conversation.reload.label_list).to include('aguardando-humano', "incidente-tecnico-#{incident.id}")
    expect(conversation.assignee_agent_bot_id).to be_nil
  end

  it 'returns duplicate without creating a second message, link, label or handoff' do
    service = described_class.new(account: account, opaque_id: evaluation.opaque_id)
    expect(service.call[:status]).to eq('accepted')

    expect { expect(service.call[:status]).to eq('duplicate') }
      .not_to change { [TechnicalIncidentDelivery.count, Message.count, TechnicalIncidentConversationLink.count] }
  end

  it 'performs no mutation when the feature is disabled before commit' do
    account.disable_features!('technical_incidents')

    expect do
      result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call
      expect(result).to include(status: 'stale', reason_code: 'feature_disabled')
    end.not_to change { [TechnicalIncidentDelivery.count, Message.count, conversation.reload.label_list] }
  end

  it 'rejects shadow evaluations even if an adapter calls commit by mistake' do
    evaluation.update!(mode: 'shadow')

    expect do
      result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call
      expect(result).to include(status: 'stale', reason_code: 'evaluation_not_active_mode')
    end.not_to change { [TechnicalIncidentDelivery.count, Message.count, conversation.reload.label_list] }
  end

  it 'rejects an expired evaluation or changed notification version' do
    evaluation.update!(expires_at: 1.minute.ago)
    expect(described_class.new(account: account, opaque_id: evaluation.opaque_id).call)
      .to include(status: 'stale', reason_code: 'evaluation_expired')

    evaluation.update!(expires_at: 10.minutes.from_now)
    incident.increment!(:notification_version)
    expect(described_class.new(account: account, opaque_id: evaluation.opaque_id).call)
      .to include(status: 'stale', reason_code: 'notification_version_changed')
  end
end
