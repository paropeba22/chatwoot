require 'rails_helper'

RSpec.describe Conversations::InactivityShadowJob do
  let(:account) { create(:account) }
  let!(:conversation) do
    create(:conversation, account: account, label_list: ['aguardando-humano'], status: :open)
  end

  it 'does nothing while the account feature is disabled' do
    expect { described_class.perform_now(account.id) }.not_to change(ConversationInactivityShadowAssessment, :count)
  end

  it 'upserts shadow-only assessments when enabled without changing the conversation' do
    account.enable_features!('conversation_inactivity_shadow')
    before_state = conversation.attributes

    expect { described_class.perform_now(account.id) }.to change(ConversationInactivityShadowAssessment, :count).by(1)

    assessment = ConversationInactivityShadowAssessment.last
    expect(assessment).to have_attributes(
      account_id: account.id,
      conversation_id: conversation.id,
      classification: 'handoff_pending'
    )
    expect(conversation.reload.attributes).to eq(before_state)
  end

  it 'does not process when another worker owns the account advisory lock' do
    account.enable_features!('conversation_inactivity_shadow')
    job = described_class.new
    allow(job).to receive(:acquire_lock).and_return(false)

    expect { job.perform_now(account.id) }.not_to change(ConversationInactivityShadowAssessment, :count)
  end
end
