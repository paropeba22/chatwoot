require 'rails_helper'

RSpec.describe Conversations::AutomationTransitionService do
  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_send_to_human_queue') } }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:account_user) { actor.account_users.find_by!(account: account) }
  let(:conversation) { create(:conversation, account: account, status: initial_status) }
  let(:initial_status) { :open }
  let(:idempotency_key) { "queue-#{SecureRandom.uuid}" }
  let(:expected_last_message_id) { nil }
  let(:attributes) do
    {
      action: 'send_to_human_queue',
      idempotency_key: idempotency_key,
      expected_last_message_id: expected_last_message_id
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

  before do
    create(:inbox_member, user: actor, inbox: conversation.inbox)
    Current.user = actor
  end

  after { Current.reset }

  describe '#call' do
    it 'projects the conversation to the human queue atomically' do
      other_assignee = create(:user, account: account)
      conversation.update!(
        assignee: other_assignee,
        label_list: %w[bot-bia priority-customer],
        custom_attributes: {
          'financeiro_state' => { 'step' => 'awaiting_invoice' },
          'cadastro_state' => { 'step' => 'awaiting_name' },
          'suporte_state' => { 'step' => 'awaiting_contract' },
          'transferencia_state' => { 'step' => 'handoff' },
          'liberacao_ativa' => true
        }
      )

      result = service.call
      conversation.reload

      expect(result.status).to eq('accepted')
      expect(conversation).to be_open
      expect(conversation.assignee_id).to be_nil
      expect(conversation.assignee_agent_bot_id).to be_nil
      expect(conversation.label_list).to contain_exactly('aguardando-humano', 'priority-customer')
      expect(conversation.custom_attributes).to include(
        'bia_retorno_humano_pendente' => true,
        'financeiro_state' => { 'step' => 'awaiting_invoice' },
        'cadastro_state' => { 'step' => 'awaiting_name' },
        'suporte_state' => { 'step' => 'awaiting_contract' },
        'transferencia_state' => { 'step' => 'handoff' },
        'liberacao_ativa' => true
      )
      expect(conversation.waiting_since).to be_present
    end

    it 'removes a native AgentBot assignment' do
      conversation.update!(assignee_agent_bot: create(:agent_bot, account: account), label_list: ['bot-bia'])

      service.call

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
      expect(conversation.label_list).to contain_exactly('aguardando-humano')
    end

    it 'removes an assignment to the actor who initiated the transition' do
      conversation.update!(assignee: actor)

      service.call

      expect(conversation.reload.assignee_id).to be_nil
      expect(conversation.label_list).to contain_exactly('aguardando-humano')
    end

    it 'creates one structured audit record and one private note' do
      expect { service.call }
        .to change(ConversationAutomationTransition, :count).by(1)
        .and change { conversation.messages.where(private: true).count }.by(1)

      transition = ConversationAutomationTransition.last
      note = transition.audit_message
      expect(transition).to have_attributes(
        account_id: account.id,
        conversation_id: conversation.id,
        actor_id: actor.id,
        action: 'send_to_human_queue',
        status: 'completed',
        reason_code: 'manual_agent_action',
        idempotency_key: idempotency_key
      )
      expect(transition.before_state).not_to include('content', 'phone', 'cpf')
      expect(note).to be_private
      expect(note.content).to include(actor.name)
      expect(note.content_attributes['automation_transition']).to eq('send_to_human_queue')
    end

    it 'does not create a public message' do
      expect { service.call }.not_to(change { conversation.messages.where(private: false).count })
    end

    %i[open pending snoozed resolved].each do |status|
      context "when the conversation is #{status}" do
        let(:initial_status) { status }

        it 'finishes open and unassigned' do
          service.call

          expect(conversation.reload).to be_open
          expect(conversation.assignee_id).to be_nil
        end
      end
    end

    it 'does not trigger inbox auto-assignment when opening the conversation' do
      conversation.inbox.update!(enable_auto_assignment: true)
      conversation.update!(status: :resolved, assignee: nil)

      service.call

      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'accepts a matching expected last non-activity message id' do
      message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox)
      attributes[:expected_last_message_id] = message.id

      expect(service.call.status).to eq('accepted')
    end

    it 'returns conflict without applying partial state when the last message changed' do
      message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox)
      attributes[:expected_last_message_id] = message.id - 1

      expect { service.call }
        .to raise_error(described_class::Conflict) { |error| expect(error.reason_code).to eq('stale_last_message') }
      expect(conversation.reload.label_list).not_to include('aguardando-humano')
      expect(ConversationAutomationTransition.count).to eq(0)
    end

    it 'returns the original result for an idempotency replay' do
      first_result = service.call
      second_result = nil

      expect { second_result = service.call }
        .not_to change(ConversationAutomationTransition, :count)
      expect(second_result.status).to eq('duplicate')
      expect(second_result.reason_code).to eq('idempotency_replay')
      expect(second_result.transition.id).to eq(first_result.transition.id)
      expect(conversation.messages.where(private: true).count).to eq(1)
    end

    it 'treats a new request against the final projection as idempotent' do
      service.call
      new_service = described_class.new(
        account: account,
        actor: actor,
        account_user: account_user,
        conversation_display_id: conversation.display_id,
        attributes: attributes.merge(idempotency_key: "queue-#{SecureRandom.uuid}")
      )
      result = nil

      expect { result = new_service.call }
        .not_to change(ConversationAutomationTransition, :count)
      expect(result.status).to eq('duplicate')
      expect(result.reason_code).to eq('already_in_human_queue')
      expect(conversation.messages.where(private: true).count).to eq(1)
    end

    it 'does not create audit artifacts when the conversation is already correctly queued' do
      conversation.update!(
        status: :open,
        assignee: nil,
        assignee_agent_bot: nil,
        label_list: %w[aguardando-humano priority-customer],
        custom_attributes: { 'bia_retorno_humano_pendente' => true }
      )
      result = nil

      expect { result = service.call }
        .not_to change(ConversationAutomationTransition, :count)
      expect(conversation.messages.where(private: true).count).to eq(0)
      expect(result.status).to eq('duplicate')
      expect(result.reason_code).to eq('already_in_human_queue')
      expect(conversation.reload.label_list).to contain_exactly('aguardando-humano', 'priority-customer')
    end

    it 'rolls back every state change when note creation fails' do
      builder = instance_double(Messages::MessageBuilder)
      allow(Messages::MessageBuilder).to receive(:new).and_return(builder)
      allow(builder).to receive(:perform).and_raise(ActiveRecord::RecordInvalid.new(Message.new))

      expect { service.call }.to raise_error(described_class::InvalidRequest)

      conversation.reload
      expect(conversation.label_list).not_to include('aguardando-humano')
      expect(conversation.custom_attributes).not_to include('bia_retorno_humano_pendente')
      expect(ConversationAutomationTransition.count).to eq(0)
    end

    it 'rejects the operation when the feature is disabled after the request starts' do
      account.disable_features!('conversation_send_to_human_queue')

      expect { service.call }.to raise_error(described_class::FeatureDisabled)
      expect(ConversationAutomationTransition.count).to eq(0)
    end

    it 'rejects an actor without access to the inbox' do
      inaccessible_actor = create(:user, account: account, role: :agent)
      inaccessible_account_user = inaccessible_actor.account_users.find_by!(account: account)
      inaccessible_service = described_class.new(
        account: account,
        actor: inaccessible_actor,
        account_user: inaccessible_account_user,
        conversation_display_id: conversation.display_id,
        attributes: attributes
      )

      expect { inaccessible_service.call }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'rejects unsupported actions' do
      attributes[:action] = 'return_to_robot'

      expect { service.call }.to raise_error(described_class::InvalidRequest) do |error|
        expect(error.reason_code).to eq('unsupported_action')
      end
    end
  end
end
