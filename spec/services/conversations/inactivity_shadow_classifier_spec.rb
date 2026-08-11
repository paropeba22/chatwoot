require 'rails_helper'

RSpec.describe Conversations::InactivityShadowClassifier do
  let(:account) { create(:account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: ['bot-bia'],
      custom_attributes: { 'bia_automation_state' => 'active', 'bia_session_generation' => 7 }
    )
  end
  let(:now) { Time.zone.parse('2026-08-05 18:00:00') }

  def create_message(message_type:, created_at: 10.minutes.ago, status: :sent)
    create(
      :message,
      account: account,
      conversation: conversation,
      inbox: conversation.inbox,
      message_type: message_type,
      status: status,
      created_at: created_at
    )
  end

  it 'uses separate customer and operation clocks' do
    create_message(message_type: :outgoing, created_at: now - 20.minutes)
    create_message(message_type: :incoming, created_at: now - 5.minutes)

    result = described_class.new(conversation, now: now).call

    expect(result).to have_attributes(
      classification: 'waiting_automation',
      customer_wait_seconds: 1200,
      operation_wait_seconds: 300,
      session_generation: 7
    )
  end

  it 'classifies a delivered outgoing message as waiting for the customer' do
    create_message(message_type: :outgoing, created_at: now - 10.minutes, status: :delivered)

    expect(described_class.new(conversation, now: now).call.classification).to eq('waiting_customer')
  end

  it 'does not call an undelivered outgoing message customer inactivity' do
    create_message(message_type: :outgoing, status: :failed)

    expect(described_class.new(conversation, now: now).call.classification).to eq('operation_pending')
  end

  it 'protects a pending context reset' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_context_reset_required' => true))

    expect(described_class.new(conversation, now: now).call).to have_attributes(
      classification: 'operation_pending', reason_code: 'context_reset_pending'
    )
  end

  it 'classifies handoff and human assignment without mutating the conversation' do
    conversation.update!(label_list: ['aguardando-humano'], custom_attributes: { 'bia_automation_state' => 'paused_human' })
    before_state = conversation.reload.attributes.deep_dup
    result = described_class.new(conversation, now: now).call

    expect(result.classification).to eq('handoff_pending')
    expect(conversation.reload.attributes).to eq(before_state)
  end

  it 'marks resolved conversations do not touch' do
    conversation.update!(status: :resolved)

    expect(described_class.new(conversation, now: now).call.classification).to eq('do_not_touch')
  end

  it 'normalizes malformed generation without raising' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_session_generation' => 'invalid'))

    expect(described_class.new(conversation, now: now).call.session_generation).to eq(0)
  end
end
