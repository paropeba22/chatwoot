require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject(:policy) { described_class.new(context, conversation) }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:account_user) { agent.account_users.find_by!(account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:context) { { user: agent, account: account, account_user: account_user } }

  before { create(:inbox_member, user: agent, inbox: conversation.inbox) }

  it 'allows a custom role with conversation access and the queue permission' do
    role = create(:custom_role, account: account, permissions: %w[conversation_manage conversation_send_to_queue])
    account_user.update!(custom_role: role)

    expect(policy.send_to_human_queue?).to be(true)
  end

  it 'denies a custom role without the queue permission' do
    role = create(:custom_role, account: account, permissions: %w[conversation_manage])
    account_user.update!(custom_role: role)

    expect(policy.send_to_human_queue?).to be(false)
  end

  it 'denies the queue permission when the custom role cannot access the conversation' do
    role = create(:custom_role, account: account, permissions: %w[conversation_participating_manage conversation_send_to_queue])
    account_user.update!(custom_role: role)

    expect(policy.send_to_human_queue?).to be(false)
  end
end
