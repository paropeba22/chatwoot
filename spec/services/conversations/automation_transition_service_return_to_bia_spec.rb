require 'rails_helper'

RSpec.describe Conversations::AutomationTransitionService do
  let(:account) do
    create(:account).tap do |record|
      record.enable_features!('conversation_send_to_human_queue', 'conversation_return_to_bia')
    end
  end
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:account_user) { actor.account_users.find_by!(account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: %w[aguardando-humano priority-customer],
      custom_attributes: existing_attributes
    )
  end
  let(:existing_attributes) do
    {
      'bia_retorno_humano_pendente' => true,
      'bia_automation_state' => 'paused_human',
      'bia_session_generation' => 4,
      'financeiro_state' => { 'etapa' => 'escolher_fatura', 'selected_invoice_id' => 'safe-reference' },
      'suporte_state' => { 'etapa' => 'aguardar_diagnostico' },
      'liberacao_ativa' => true
    }
  end
  let!(:latest_customer_message) do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)
  end
  let(:idempotency_key) { "bia-#{SecureRandom.uuid}" }
  let(:attributes) do
    {
      action: 'return_to_bia',
      idempotency_key: idempotency_key,
      expected_last_message_id: latest_customer_message.id,
      expected_assignee_id: conversation.assignee_id,
      expected_session_generation: 4
    }
  end
  let(:service) do
    described_class.new(
      account: account,
      actor: actor,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: attributes
    )
  end

  before { Current.user = actor }

  after { Current.reset }

  it 'projects an eligible human conversation to a fresh Bia session', :aggregate_failures do
    human = create(:user, account: account)
    agent_bot = create(:agent_bot, account: account)
    conversation.update!(assignee_agent_bot: agent_bot)
    conversation.update!(assignee: human)
    attributes[:expected_assignee_id] = human.id

    result = service.call
    conversation.reload

    expect(result).to have_attributes(status: 'accepted', reason_code: 'returned_to_bia')
    expect(conversation).to be_open
    expect(conversation.assignee_id).to be_nil
    expect(conversation.assignee_agent_bot_id).to be_nil
    expect(conversation.label_list).to contain_exactly('bot-bia', 'priority-customer')
    expect(conversation.waiting_since).to be_nil
    expect(conversation.custom_attributes).to include(
      'bia_retorno_humano_pendente' => false,
      'bia_automation_state' => 'active',
      'bia_session_generation' => 5,
      'bia_resume_after_message_id' => latest_customer_message.id,
      'bia_context_reset_required' => true,
      'financeiro_state' => existing_attributes['financeiro_state'],
      'suporte_state' => existing_attributes['suporte_state'],
      'liberacao_ativa' => true
    )
    expect(conversation.custom_attributes['bia_returned_at']).to be_present
  end

  it 'does not create a public message and creates one private audit note' do
    public_message_count = conversation.messages.where(private: false).count

    expect { service.call }.to change { conversation.messages.where(private: true).count }.by(1)
    expect(conversation.messages.where(private: false).count).to eq(public_message_count)

    transition = conversation.automation_transitions.last
    expect(transition).to have_attributes(action: 'return_to_bia', status: 'completed')
    expect(transition.audit_message).to be_private
    expect(transition.audit_message.content_attributes['automation_transition']).to eq('return_to_bia')
    expect(transition.before_state.keys).not_to include('financeiro_state', 'suporte_state')
  end

  it 'returns an idempotency replay without duplicating audit artifacts' do
    first = service.call
    second = service.call

    expect(second).to have_attributes(status: 'duplicate', reason_code: 'idempotency_replay')
    expect(second.transition.id).to eq(first.transition.id)
    expect(conversation.automation_transitions.where(action: 'return_to_bia').count).to eq(1)
    expect(conversation.messages.where(private: true).count).to eq(1)
  end

  it 'returns already_with_bia for a different request against the final state' do
    service.call
    replay = described_class.new(
      account: account,
      actor: actor,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: attributes.merge(idempotency_key: "bia-#{SecureRandom.uuid}")
    ).call

    expect(replay).to have_attributes(status: 'duplicate', reason_code: 'already_with_bia')
    expect(conversation.messages.where(private: true).count).to eq(1)
  end

  it 'initializes a safe generation for a legacy eligible conversation' do
    conversation.update!(
      custom_attributes: { 'bia_retorno_humano_pendente' => true },
      label_list: ['aguardando-humano']
    )
    attributes[:expected_session_generation] = 0

    service.call

    expect(conversation.reload.custom_attributes).to include(
      'bia_automation_state' => 'active',
      'bia_session_generation' => 1,
      'bia_context_reset_required' => true
    )
  end

  it 'rejects resolved, pending, and snoozed conversations without partial state' do
    %i[resolved pending snoozed].each do |status|
      conversation.update!(status: status)

      expect { service.call }.to raise_error(described_class::Conflict) do |error|
        expect(error.reason_code).to eq('conversation_not_open')
      end
      expect(conversation.reload.label_list).to include('aguardando-humano')
      expect(conversation.automation_transitions.where(action: 'return_to_bia')).to be_empty
    end
  end

  it 'rejects a conversation without evidence that Bia managed it' do
    conversation.update!(label_list: [], custom_attributes: {})
    attributes[:expected_session_generation] = 0

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('bia_inbox_incompatible')
    end
  end

  it 'rejects a stale message' do
    attributes[:expected_last_message_id] = latest_customer_message.id - 1
    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_last_message')
    end
  end

  it 'rejects a changed assignee' do
    attributes[:expected_assignee_id] = create(:user, account: account).id
    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_assignee')
    end
  end

  it 'rejects a stale session generation before changing the projection' do
    attributes[:expected_session_generation] = 3

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_session_generation')
    end
    expect(conversation.reload.custom_attributes['bia_session_generation']).to eq(4)
    expect(conversation.label_list).to include('aguardando-humano')
  end

  it 'rejects a regular agent even with inbox access' do
    regular_agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: regular_agent, inbox: conversation.inbox)
    regular_service = described_class.new(
      account: account,
      actor: regular_agent,
      account_user: regular_agent.account_users.find_by!(account: account),
      conversation_display_id: conversation.display_id,
      attributes: attributes
    )

    expect { regular_service.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects the action while its independent feature is disabled' do
    account.disable_features!('conversation_return_to_bia')

    expect { service.call }.to raise_error(described_class::FeatureDisabled)
  end

  it 'rolls back the projection when audit note creation fails' do
    builder = instance_double(Messages::MessageBuilder)
    allow(Messages::MessageBuilder).to receive(:new).and_return(builder)
    allow(builder).to receive(:perform).and_raise(ActiveRecord::RecordInvalid.new(Message.new))

    expect { service.call }.to raise_error(described_class::InvalidRequest)

    expect(conversation.reload.label_list).to include('aguardando-humano')
    expect(conversation.custom_attributes['bia_automation_state']).to eq('paused_human')
    expect(conversation.automation_transitions.where(action: 'return_to_bia')).to be_empty
  end

  it 'preserves the queue transition and increments generation across alternating actions' do
    return_result = service.call
    queue_result = described_class.new(
      account: account,
      actor: actor,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: {
        action: 'send_to_human_queue',
        idempotency_key: "queue-#{SecureRandom.uuid}"
      }
    ).call

    expect(return_result.status).to eq('accepted')
    expect(queue_result.status).to eq('accepted')
    expect(conversation.reload.custom_attributes).to include(
      'bia_automation_state' => 'paused_human',
      'bia_session_generation' => 6,
      'bia_retorno_humano_pendente' => true
    )
    expect(conversation.label_list).to include('aguardando-humano')
    expect(conversation.label_list).not_to include('bot-bia')
  end
end
