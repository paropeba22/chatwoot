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
        semantic_confidence: 0.95,
        topic_change: false,
        needs_clarification: false
      },
      candidate_snapshot: [incident.customer_visible_snapshot]
    )
  end

  around do |example|
    with_modified_env(
      TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'active',
      TECHNICAL_INCIDENTS_OUTBOX_ENABLED: 'true'
    ) { example.run }
  end

  before do
    allow(TechnicalIncidents::OutboxDispatchJob).to receive(:perform_later)
  end

  it 'atomically reserves the outbox without creating a message, link, label, note, or handoff' do
    expect do
      result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call
      expect(result).to include(status: 'accepted', reason_code: 'outbox_reserved')
    end.to change(TechnicalIncidentDelivery, :count).by(1)
      .and change { evaluation.reload.status }.from('general_match').to('accepted')

    delivery = account.technical_incident_deliveries.sole
    expect(delivery).to have_attributes(
      outbox_state: 'pending',
      message_state: 'pending',
      transport_state: 'pending',
      link_state: 'pending',
      handoff_state: 'pending'
    )
    expect(account.technical_incident_conversation_links).to be_empty
    expect(conversation.reload.messages).to be_empty
    expect(conversation.label_list).not_to include('aguardando-humano')
    expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
  end

  it 'returns duplicate without reserving a second outbox row' do
    service = described_class.new(account: account, opaque_id: evaluation.opaque_id)
    expect(service.call[:status]).to eq('accepted')

    expect { expect(service.call[:status]).to eq('duplicate') }
      .not_to change { [TechnicalIncidentDelivery.count, Message.count, TechnicalIncidentConversationLink.count] }
  end

  it 'preserves the database outbox reservation when Redis enqueue fails after commit' do
    allow(TechnicalIncidents::OutboxDispatchJob).to receive(:perform_later).and_raise(Redis::BaseError)

    result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call

    expect(result[:status]).to eq('accepted')
    expect(account.technical_incident_deliveries.sole.outbox_state).to eq('pending')
    expect(evaluation.reload.status).to eq('accepted')
  end

  it 'rolls back evaluation acceptance when reservation fails before commit' do
    allow(account.technical_incident_deliveries).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect do
      described_class.new(account: account, opaque_id: evaluation.opaque_id).call
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(evaluation.reload.status).to eq('general_match')
  end

  it 'does not reserve when server automation is disabled or shadow' do
    %w[disabled shadow].each do |mode|
      with_modified_env TECHNICAL_INCIDENTS_AUTOMATION_MODE: mode do
        result = described_class.new(account: account, opaque_id: evaluation.opaque_id).call
        expect(result).to include(status: 'stale', reason_code: 'server_automation_not_active')
      end
    end
    expect(account.technical_incident_deliveries).to be_empty
  end

  it 'rejects shadow evaluations and semantic gates at commit time' do
    evaluation.update!(mode: 'shadow')
    expect(described_class.new(account: account, opaque_id: evaluation.opaque_id).call)
      .to include(status: 'stale', reason_code: 'evaluation_not_active_mode')

    evaluation.update!(mode: 'active', classification: evaluation.classification.merge('topic_change' => true))
    expect(described_class.new(account: account, opaque_id: evaluation.opaque_id).call)
      .to include(status: 'stale', reason_code: 'semantic_compatibility_changed')
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
