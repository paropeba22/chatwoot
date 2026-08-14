require 'rails_helper'

RSpec.describe Conversations::OperationalBucket do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def build_conversation(attributes = {})
    create(:conversation, { account: account, status: :open }.merge(attributes))
  end

  it 'projects canonical Bia, human queue, and mine states exclusively', :aggregate_failures do
    bia = build_conversation(
      label_list: ['bot-bia'],
      custom_attributes: { 'bia_automation_state' => 'active', 'bia_session_generation' => 3 }
    )
    queue = build_conversation(
      label_list: ['aguardando-humano'],
      custom_attributes: { 'bia_automation_state' => 'paused_human', 'bia_session_generation' => 2 }
    )
    mine = build_conversation(assignee: user)

    expect(described_class.new(bia, current_user: user).call.bucket).to eq('bia')
    expect(described_class.new(queue, current_user: user).call.bucket).to eq('human_queue')
    expect(described_class.new(mine, current_user: user).call.bucket).to eq('mine')
  end

  it 'uses safe precedence and marks contradictory historical state' do
    conversation = build_conversation(assignee: user, label_list: %w[bot-bia aguardando-humano])

    result = described_class.new(conversation, current_user: user).call

    expect(result).to have_attributes(bucket: 'mine', reason: 'human_assignee_precedence', inconsistent: true)
  end

  it 'moves a Bia-labeled conversation exclusively to mine when the current user is assigned' do
    conversation = build_conversation(assignee: user, label_list: ['bot-bia'])
    relation = account.conversations.where(id: conversation.id)

    expect(described_class.new(conversation, current_user: user).call.bucket).to eq('mine')
    expect(described_class.scope(relation, bucket: 'mine', current_user: user)).to contain_exactly(conversation)
    expect(described_class.scope(relation, bucket: 'bia', current_user: user)).to be_empty
    expect(described_class.scope(relation, bucket: 'human_queue', current_user: user)).to be_empty
  end

  it 'keeps a native AgentBot assignment out of all three buckets' do
    conversation = build_conversation(assignee_agent_bot: create(:agent_bot, account: account), label_list: ['bot-bia'])

    expect(described_class.new(conversation, current_user: user).call.bucket).to be_nil
  end

  it 'uses the same scopes for lists and counts' do
    mine = build_conversation(assignee: user)
    queue = build_conversation(label_list: ['aguardando-humano'])
    bia = build_conversation(label_list: ['bot-bia'])
    relation = account.conversations.where(id: [mine.id, queue.id, bia.id])

    expect(described_class.counts(relation, current_user: user)).to eq('mine' => 1, 'human_queue' => 1, 'bia' => 1)
    expect(described_class.scope(relation, bucket: 'human_queue', current_user: user)).to contain_exactly(queue)
  end
end
