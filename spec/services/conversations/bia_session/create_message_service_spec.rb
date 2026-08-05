require 'rails_helper'

RSpec.describe Conversations::BiaSession::CreateMessageService do
  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_return_to_bia') } }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: ['bot-bia'],
      custom_attributes: {
        'bia_automation_state' => 'active',
        'bia_session_generation' => 5,
        'bia_resume_after_message_id' => 0,
        'bia_context_reset_required' => false,
        'bia_retorno_humano_pendente' => false
      }
    )
  end
  let!(:source_message) do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)
  end
  let(:attributes) do
    {
      expected_generation: 5,
      source_message_id: source_message.id,
      idempotency_key: "bia-send-#{SecureRandom.uuid}",
      content: 'Resposta simulada',
      content_type: 'text',
      private: false
    }
  end

  subject(:service) do
    described_class.new(
      account: account,
      actor: actor,
      account_user: actor.account_users.find_by!(account: account),
      conversation_display_id: conversation.display_id,
      attributes: attributes
    )
  end

  it 'creates one public message under the generation lock and replays idempotently' do
    first = service.call
    second = service.call

    expect(first).to have_attributes(status: 'accepted', reason_code: 'message_created')
    expect(first.message).to be_outgoing
    expect(first.message).not_to be_private
    expect(second).to have_attributes(status: 'duplicate', reason_code: 'idempotency_replay')
    expect(second.message.id).to eq(first.message.id)
    expect(conversation.messages.where(content: 'Resposta simulada').count).to eq(1)
  end

  it 'blocks a generation 3 execution after the conversation advances to generation 5' do
    attributes[:expected_generation] = 3

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_session_generation')
    end
    expect(conversation.messages.where(content: 'Resposta simulada')).to be_empty
  end

  it 'blocks sending while context reset remains required' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_context_reset_required' => true))

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('context_reset_required')
    end
  end
end
