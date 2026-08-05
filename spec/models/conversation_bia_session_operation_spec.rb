require 'rails_helper'

RSpec.describe ConversationBiaSessionOperation do
  subject(:operation) { build(:conversation_bia_session_operation) }

  it { is_expected.to be_valid }

  it 'rejects a source message from another conversation' do
    operation.source_message = create(:message, account: operation.account)

    expect(operation).not_to be_valid
    expect(operation.errors[:source_message]).to be_present
  end

  it 'isolates idempotency by operation while rejecting a duplicate operation key' do
    existing = create(:conversation_bia_session_operation)
    duplicate = build(
      :conversation_bia_session_operation,
      account: existing.account,
      conversation: existing.conversation,
      source_message: existing.source_message,
      operation: existing.operation,
      idempotency_key: existing.idempotency_key
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:idempotency_key]).to be_present

    duplicate.operation = 'create_message'
    duplicate.reset_profile = nil
    duplicate.reason_code = 'message_created'
    expect(duplicate).to be_valid
  end
end
