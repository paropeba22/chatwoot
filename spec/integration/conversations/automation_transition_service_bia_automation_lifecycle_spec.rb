require 'rails_helper'

RSpec.describe Conversations::AutomationTransitionService, 'Bia automation lifecycle', type: :service do
  let(:account) do
    create(:account).tap do |record|
      record.enable_features!(
        'conversation_send_to_human_queue',
        'conversation_return_to_bia',
        'conversation_operational_buckets'
      )
    end
  end
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:account_user) { administrator.account_users.find_by!(account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: ['bot-bia'],
      custom_attributes: {
        'bia_automation_state' => 'active',
        'bia_session_generation' => 1,
        'bia_context_reset_required' => false,
        'bia_retorno_humano_pendente' => false,
        'financeiro_state' => { 'etapa' => 'confirmacao', 'selected_invoice_id' => 'fixture-reference' }
      }
    )
  end
  let!(:source_message) do
    create(
      :message,
      account: account,
      conversation: conversation,
      inbox: conversation.inbox,
      message_type: :incoming,
      private: false
    )
  end

  def transition(action, generation)
    Conversations::AutomationTransitionService.new(
      account: account,
      actor: administrator,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: {
        action: action,
        idempotency_key: "#{action}-#{SecureRandom.uuid}",
        expected_last_message_id: conversation.messages.where.not(message_type: :activity).maximum(:id),
        expected_assignee_id: conversation.assignee_id,
        expected_session_generation: generation
      }
    ).call
  end

  it 'moves Bia to human queue and back, then resets on a newer incoming message', :aggregate_failures do
    expect(source_message).to be_incoming
    expect { transition('send_to_human_queue', 1) }.not_to(change { public_outgoing_count })
    expect(conversation.reload.custom_attributes).to include(
      'bia_automation_state' => 'paused_human',
      'bia_session_generation' => 2
    )
    expect(Conversations::OperationalBucket.new(conversation).call.bucket).to eq('human_queue')

    expect { transition('return_to_bia', 2) }.not_to(change { public_outgoing_count })
    conversation.reload
    expect(conversation.custom_attributes).to include(
      'bia_automation_state' => 'active',
      'bia_session_generation' => 3,
      'bia_context_reset_required' => true
    )
    expect(Conversations::OperationalBucket.new(conversation).call.bucket).to eq('bia')

    next_message = create(
      :message,
      account: account,
      conversation: conversation,
      inbox: conversation.inbox,
      message_type: :incoming,
      private: false
    )
    reset_result = Conversations::BiaSession::ResetContextService.new(
      account: account,
      actor: administrator,
      account_user: account_user,
      conversation_display_id: conversation.display_id,
      attributes: {
        expected_generation: 3,
        source_message_id: next_message.id,
        idempotency_key: "bia-reset-#{SecureRandom.uuid}",
        reset_profile: 'bia_session_v1'
      }
    ).call

    expect(reset_result.reason_code).to eq('context_reset_applied')
    expect(conversation.reload.custom_attributes).to include(
      'bia_session_generation' => 3,
      'bia_context_reset_required' => false,
      'bia_context_reset_message_id' => next_message.id
    )
    expect(conversation.custom_attributes.dig('financeiro_state', 'etapa')).to be_nil
    expect(Conversations::InactivityShadowClassifier.new(conversation).call.classification).to eq('waiting_automation')
    expect(public_outgoing_count).to eq(0)
  end

  private

  def public_outgoing_count
    conversation.messages.outgoing.where(private: false).count
  end
end
