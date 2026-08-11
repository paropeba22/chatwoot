require 'rails_helper'

RSpec.describe ConversationAutomationTransition do
  subject(:transition) { build(:conversation_automation_transition, account: account, conversation: conversation, actor: actor) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:actor) { create(:user, account: account) }

  it { is_expected.to belong_to(:account) }
  it { is_expected.to belong_to(:conversation) }
  it { is_expected.to belong_to(:actor).class_name('User').optional }
  it { is_expected.to belong_to(:audit_message).class_name('Message').optional }

  it 'has a unique database index for the idempotency scope' do
    index = described_class.connection.indexes(described_class.table_name).find do |candidate|
      candidate.name == 'idx_conversation_automation_transitions_idempotency'
    end

    expect(index.unique).to be(true)
    expect(index.columns).to eq(%w[account_id conversation_id action idempotency_key])
  end

  it 'accepts both implemented actions and rejects unknown actions' do
    transition.action = 'return_to_bia'

    expect(transition).to be_valid

    transition.action = 'unknown'

    expect(transition).not_to be_valid
    expect(transition.errors[:action]).to be_present
  end

  it 'rejects an actor from another account' do
    transition.actor = create(:user, account: create(:account))

    expect(transition).not_to be_valid
    expect(transition.errors[:actor]).to be_present
  end

  it 'rejects a conversation from another account' do
    transition.conversation = create(:conversation, account: create(:account))

    expect(transition).not_to be_valid
    expect(transition.errors[:conversation]).to be_present
  end

  it 'enforces idempotency within account, conversation, and action' do
    create(:conversation_automation_transition,
           account: account,
           conversation: conversation,
           actor: actor,
           idempotency_key: transition.idempotency_key)

    expect(transition).not_to be_valid
    expect(transition.errors[:idempotency_key]).to be_present
  end

  it 'allows the same idempotency key for another conversation in the account' do
    create(:conversation_automation_transition,
           account: account,
           conversation: create(:conversation, account: account),
           actor: actor,
           idempotency_key: transition.idempotency_key)

    expect(transition).to be_valid
  end

  it 'isolates the same idempotency key by action' do
    create(:conversation_automation_transition,
           account: account,
           conversation: conversation,
           actor: actor,
           action: 'send_to_human_queue',
           idempotency_key: transition.idempotency_key)
    transition.action = 'return_to_bia'

    expect(transition).to be_valid
  end
end
