require 'rails_helper'

RSpec.describe TechnicalIncidents::OutboxProcessor do
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
  let(:delivery) do
    allow(TechnicalIncidents::OutboxDispatchJob).to receive(:perform_later)
    TechnicalIncidents::CommitService.new(account: account, opaque_id: evaluation.opaque_id).call
    account.technical_incident_deliveries.sole
  end

  around do |example|
    with_modified_env(
      TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'active',
      TECHNICAL_INCIDENTS_OUTBOX_ENABLED: 'true',
      TECHNICAL_INCIDENTS_DELIVERY_ENABLED: 'true'
    ) { example.run }
  end

  it 'processes message, transport, link, labels, note, handoff and audit independently' do
    message = create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: agent_bot,
      message_type: :outgoing,
      status: :delivered,
      content: incident.customer_message
    )
    adapter = instance_double(
      TechnicalIncidents::DeliveryAdapters::Base,
      create_message!: message,
      enqueue_transport!: 'fake'
    )
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)

    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(
      outbox_state: 'completed',
      message_state: 'created',
      transport_state: 'delivered',
      link_state: 'completed',
      label_state: 'completed',
      note_state: 'completed',
      handoff_state: 'completed',
      audit_state: 'completed'
    )
    expect(conversation.reload.label_list).to include('aguardando-humano', "incidente-tecnico-#{incident.id}")
    expect(conversation.assignee_agent_bot_id).to be_nil
    expect(delivery.message_id).to eq(message.id)
  end

  it 'does not hand off before transport confirmation and remains retryable' do
    message = create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: agent_bot,
      message_type: :outgoing,
      status: :sent
    )
    adapter = instance_double(
      TechnicalIncidents::DeliveryAdapters::Base,
      create_message!: message,
      enqueue_transport!: 'fake'
    )
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)

    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(outbox_state: 'retry', transport_state: 'queued', handoff_state: 'pending')
    expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
    expect(conversation.label_list).not_to include('aguardando-humano')
  end

  it 'is idempotent when the same delivery is processed again' do
    message = create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: agent_bot,
      message_type: :outgoing,
      status: :delivered
    )
    adapter = instance_double(
      TechnicalIncidents::DeliveryAdapters::Base,
      create_message!: message,
      enqueue_transport!: 'fake'
    )
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)

    service = described_class.new(delivery.id)
    service.call
    counts = [Message.count, TechnicalIncidentConversationLink.count, TechnicalIncidentUpdate.count]
    described_class.new(delivery.id).call

    expect([Message.count, TechnicalIncidentConversationLink.count, TechnicalIncidentUpdate.count]).to eq(counts)
  end

  it 'fails safely for an unsupported inbox without creating a message or handoff' do
    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(outbox_state: 'failed_terminal', last_error_code: a_string_starting_with('unsupported_inbox'))
    expect(delivery.message).to be_nil
    expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
  end

  it 'recovers a stale worker lease and does not lose work when enqueue fails' do
    delivery.update!(
      outbox_state: 'processing',
      locked_at: 10.minutes.ago,
      lock_token: SecureRandom.uuid
    )
    allow(TechnicalIncidents::OutboxProcessJob).to receive(:perform_later).and_raise(Redis::BaseError)

    TechnicalIncidents::OutboxDispatchJob.perform_now

    expect(delivery.reload.outbox_state).to eq('retry')
    expect(delivery.next_retry_at).to be_present
  end

  it 'does not let a second worker take a live lease' do
    delivery.update!(
      outbox_state: 'processing',
      locked_at: Time.current,
      lock_token: SecureRandom.uuid
    )

    expect { described_class.new(delivery.id).call }
      .not_to change { delivery.reload.attributes.slice('outbox_state', 'lock_token', 'attempts') }
  end

  it 'does not claim or mutate a delivery while the outbox switch is off' do
    adapter = instance_double(TechnicalIncidents::DeliveryAdapters::Base)
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)
    original = delivery.attributes.slice('outbox_state', 'lock_token', 'attempts', 'updated_at')

    with_modified_env TECHNICAL_INCIDENTS_OUTBOX_ENABLED: 'false' do
      described_class.new(delivery.id).call
    end

    expect(delivery.reload.attributes.slice(*original.keys)).to eq(original)
    expect(adapter).not_to have_received(:create_message!)
  end

  it 'rechecks the account feature and delivery switch before any side effect' do
    adapter = instance_double(TechnicalIncidents::DeliveryAdapters::Base)
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)

    with_modified_env TECHNICAL_INCIDENTS_DELIVERY_ENABLED: 'false' do
      described_class.new(delivery.id).call
    end
    expect(delivery.reload).to have_attributes(
      outbox_state: 'retry',
      message_state: 'pending',
      link_state: 'pending',
      attempts: 0,
      last_error_code: 'delivery_disabled'
    )

    delivery.update!(outbox_state: 'pending', next_retry_at: Time.current)
    account.disable_features!('technical_incidents')
    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(
      outbox_state: 'failed_terminal',
      message_state: 'pending',
      link_state: 'pending',
      last_error_code: 'feature_disabled'
    )
    expect(adapter).not_to have_received(:create_message!)
  end

  %w[disabled shadow].each do |server_mode|
    it "rechecks #{server_mode} automation mode before any outbox side effect" do
      adapter = instance_double(TechnicalIncidents::DeliveryAdapters::Base)
      allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)

      with_modified_env TECHNICAL_INCIDENTS_AUTOMATION_MODE: server_mode do
        described_class.new(delivery.id).call
      end

      expect(delivery.reload).to have_attributes(
        outbox_state: 'retry',
        message_state: 'pending',
        link_state: 'pending',
        label_state: 'pending',
        note_state: 'pending',
        handoff_state: 'pending',
        attempts: 0,
        last_error_code: 'server_automation_not_active'
      )
      expect(delivery.message).to be_nil
      expect(delivery.technical_incident_conversation_link).to be_nil
      expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
      expect(adapter).not_to have_received(:create_message!)
    end
  end

  it 'records a retryable label failure and never proceeds to note or handoff' do
    message = create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: agent_bot,
      message_type: :outgoing,
      status: :delivered
    )
    adapter = instance_double(
      TechnicalIncidents::DeliveryAdapters::Base,
      create_message!: message,
      enqueue_transport!: 'fake'
    )
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)
    allow_any_instance_of(Conversation).to receive(:update_labels).and_raise(ActiveRecord::Deadlocked)

    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(
      outbox_state: 'retry',
      label_state: 'failed_retryable',
      note_state: 'pending',
      handoff_state: 'pending'
    )
  end

  it 'records a retryable handoff failure without repeating completed earlier dimensions' do
    message = create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: agent_bot,
      message_type: :outgoing,
      status: :delivered
    )
    adapter = instance_double(
      TechnicalIncidents::DeliveryAdapters::Base,
      create_message!: message,
      enqueue_transport!: 'fake'
    )
    allow(TechnicalIncidents::DeliveryAdapters).to receive(:for).and_return(adapter)
    allow_any_instance_of(Conversation).to receive(:bot_handoff!).and_raise(ActiveRecord::Deadlocked)

    described_class.new(delivery.id).call

    expect(delivery.reload).to have_attributes(
      outbox_state: 'retry',
      link_state: 'completed',
      message_state: 'created',
      transport_state: 'delivered',
      label_state: 'completed',
      note_state: 'completed',
      handoff_state: 'failed_retryable',
      audit_state: 'pending'
    )
  end
end
