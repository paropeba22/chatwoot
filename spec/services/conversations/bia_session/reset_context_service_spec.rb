require 'rails_helper'

RSpec.describe Conversations::BiaSession::ResetContextService do
  subject(:service) do
    described_class.new(
      account: account,
      actor: actor,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: attributes
    )
  end

  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_return_to_bia') } }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:account_user) { actor.account_users.find_by!(account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: %w[bot-bia retained],
      custom_attributes: {
        'bia_automation_state' => 'active',
        'bia_session_generation' => 5,
        'bia_resume_after_message_id' => boundary_message.id,
        'bia_context_reset_required' => true,
        'bia_retorno_humano_pendente' => false,
        'bia_apresentada' => true,
        'financeiro_state' => { 'etapa' => 'confirmacao', 'selected_invoice_id' => 'stable-reference', 'unknown' => 'preserved' },
        'suporte_state' => { 'step' => 'diagnostic', 'contract_id' => 'stable-contract' },
        'unrelated' => { 'kept' => true },
        'liberacao_ativa' => true
      }
    )
  end
  let!(:boundary_message) do
    create(:message, account: account, conversation: conversation_seed, inbox: conversation_seed.inbox, message_type: :incoming, private: false)
  end
  let(:conversation_seed) { create(:conversation, account: account) }
  let!(:source_message) do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)
  end
  let(:attributes) do
    {
      expected_generation: 5,
      source_message_id: source_message.id,
      idempotency_key: "bia-reset-#{SecureRandom.uuid}",
      reset_profile: 'bia_session_v1'
    }
  end

  before do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_resume_after_message_id' => boundary_message.id))
  end

  it 'applies the canonical reset under the current generation without replacing unrelated attributes', :aggregate_failures do
    result = service.call
    updated = conversation.reload.custom_attributes

    expect(result).to have_attributes(status: 'accepted', reason_code: 'context_reset_applied')
    expect(updated).to include(
      'bia_session_generation' => 5,
      'bia_resume_after_message_id' => boundary_message.id,
      'bia_context_reset_required' => false,
      'bia_context_reset_generation' => 5,
      'bia_context_reset_message_id' => source_message.id,
      'bia_apresentada' => true,
      'unrelated' => { 'kept' => true }
    )
    expect(updated).not_to have_key('liberacao_ativa')
    expect(updated['financeiro_state']).to eq('selected_invoice_id' => 'stable-reference', 'unknown' => 'preserved')
    expect(updated['suporte_state']).to eq('contract_id' => 'stable-contract')
    expect(result.operation.attributes_size_after).to be_positive
  end

  it 'replays the same idempotent operation without a second mutation' do
    first = service.call
    second = service.call

    expect(second).to have_attributes(status: 'duplicate', reason_code: 'idempotency_replay')
    expect(second.operation.id).to eq(first.operation.id)
    expect(conversation.bia_session_operations.count).to eq(1)
  end

  it 'fails closed when the generation changed and preserves concurrent attributes' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_session_generation' => 6, 'concurrent' => 'kept'))

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_session_generation')
    end
    expect(conversation.reload.custom_attributes).to include('bia_session_generation' => 6, 'concurrent' => 'kept')
    expect(conversation.bia_session_operations).to be_empty
  end

  it 'rejects an older source when a newer public incoming message exists' do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)

    expect { service.call }.to raise_error(described_class::Conflict) do |error|
      expect(error.reason_code).to eq('stale_source_message')
    end
  end

  it 'rolls back all changes when the operation record fails' do
    operation = ConversationBiaSessionOperation.new
    operation.errors.add(:base, 'controlled persistence failure')
    operation_writer = instance_double(ActiveRecord::Associations::CollectionProxy)
    allow(operation_writer).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(operation))
    failing_service_class = Class.new(described_class) do
      define_method(:operation_repository) { |_conversation| operation_writer }
    end
    original = conversation.custom_attributes.deep_dup

    expect do
      failing_service_class.new(
        account: account,
        actor: actor,
        account_user: account_user,
        conversation_display_id: conversation.display_id,
        attributes: attributes
      ).call
    end.to raise_error(described_class::InvalidRequest)
    expect(conversation.reload.custom_attributes).to eq(original)
  end
end
