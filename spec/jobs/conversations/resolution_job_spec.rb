require 'rails_helper'

RSpec.describe Conversations::ResolutionJob do
  subject(:job) { described_class.perform_later(account: account) }

  let!(:account) { create(:account) }
  let(:label) { create(:label, title: 'auto-resolved', account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account: account)
      .on_queue('low')
  end

  it 'does nothing when there is no auto resolve duration' do
    described_class.perform_now(account: account)
    expect(conversation.reload.status).to eq('open')
  end

  context 'when auto_resolve_ignore_waiting is true' do
    it 'resolves non-waiting conversations if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update(last_activity_at: 13.days.ago, waiting_since: nil)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'does not resolve waiting conversations even if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update(last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('open')
    end
  end

  context 'when auto_resolve_ignore_waiting is false' do
    it 'resolves all conversations if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
      # Create one waiting conversation and one non-waiting conversation
      waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      non_waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

      described_class.perform_now(account: account)

      expect(waiting_conversation.reload.status).to eq('resolved')
      expect(non_waiting_conversation.reload.status).to eq('resolved')
    end
  end

  context 'when conversations are managed by a human' do
    let(:stale_at) { 13.days.ago }

    before do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false)
    end

    it 'excludes human responsibility in SQL while preserving legitimate auto-resolve candidates' do
      assigned = create(:conversation, account: account, assignee: create(:user), last_activity_at: stale_at)
      human_queue = create(
        :conversation,
        account: account,
        label_list: ['aguardando-humano'],
        last_activity_at: stale_at
      )
      paused = create(
        :conversation,
        account: account,
        custom_attributes: { 'bia_automation_state' => 'paused_human' },
        last_activity_at: stale_at
      )
      active_bia = create(
        :conversation,
        account: account,
        label_list: ['bot-bia'],
        custom_attributes: { 'bia_automation_state' => 'active' },
        last_activity_at: stale_at
      )
      ordinary = create(:conversation, account: account, last_activity_at: stale_at)
      recent = create(:conversation, account: account, last_activity_at: 1.hour.ago)

      eligible_ids = account.conversations.resolvable_all(account.auto_resolve_after).pluck(:id)

      expect(eligible_ids).to include(active_bia.id, ordinary.id)
      expect(eligible_ids).not_to include(assigned.id, human_queue.id, paused.id, recent.id)
    end

    it 'does not resolve human-managed conversations and still resolves active Bia and ordinary conversations' do
      assigned = create(:conversation, account: account, assignee: create(:user), last_activity_at: stale_at)
      human_queue = create(
        :conversation,
        account: account,
        label_list: ['aguardando-humano'],
        last_activity_at: stale_at
      )
      paused = create(
        :conversation,
        account: account,
        custom_attributes: { 'bia_automation_state' => 'paused_human' },
        last_activity_at: stale_at
      )
      active_bia = create(
        :conversation,
        account: account,
        label_list: ['bot-bia'],
        custom_attributes: { 'bia_automation_state' => 'active' },
        last_activity_at: stale_at
      )
      ordinary = create(:conversation, account: account, last_activity_at: stale_at)

      described_class.perform_now(account: account)

      expect([assigned, human_queue, paused].map { |record| record.reload.status }).to all(eq('open'))
      expect([active_bia, ordinary].map { |record| record.reload.status }).to all(eq('resolved'))
    end

    it 'keeps the same protection when waiting conversations are ignored' do
      account.update(auto_resolve_ignore_waiting: true)
      assigned = create(:conversation, account: account, assignee: create(:user), last_activity_at: stale_at)
      ordinary = create(:conversation, account: account, last_activity_at: stale_at)
      assigned.update!(waiting_since: nil)
      ordinary.update!(waiting_since: nil)

      described_class.perform_now(account: account)

      expect(assigned.reload.status).to eq('open')
      expect(ordinary.reload.status).to eq('resolved')
    end
  end

  # When a contact is deleted, there's a brief window (~50-150ms) where contact_id becomes nil
  # but conversations still exist. If ResolutionJob runs during this window, muted? can crash
  # trying to call blocked? on nil. Fixes # (issue).
  it 'skips orphan conversations without a contact' do
    account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
    orphan_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)
    orphan_conversation.update_columns(contact_id: nil, contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations
    resolvable_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

    described_class.perform_now(account: account)

    expect(orphan_conversation.reload.status).to eq('open')
    expect(resolvable_conversation.reload.status).to eq('resolved')
  end

  it 'adds a label after resolution' do
    account.update(auto_resolve_label: 'auto-resolved', auto_resolve_after: 14_400)
    conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('resolved')
    expect(conversation.reload.label_list).to include('auto-resolved')
  end

  it 'resolves only a limited number of conversations in a single execution' do
    stub_const('Limits::BULK_ACTIONS_LIMIT', 2)
    account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
    create_list(:conversation, 3, account: account, last_activity_at: 13.days.ago)
    described_class.perform_now(account: account)
    expect(account.conversations.resolved.count).to eq(Limits::BULK_ACTIONS_LIMIT)
  end
end
