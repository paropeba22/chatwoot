require 'rails_helper'

RSpec.describe 'Conversation automation transition concurrency', :non_transactional do
  self.use_transactional_tests = false

  it 'lets one concurrent request apply the transition and makes the other idempotent' do
    account = create(:account).tap { |record| record.enable_features!('conversation_send_to_human_queue') }
    actors = create_list(:user, 2, account: account, role: :agent)
    conversation = create(:conversation, account: account, label_list: ['bot-bia'])
    actors.each { |actor| create(:inbox_member, user: actor, inbox: conversation.inbox) }
    barrier = Concurrent::CyclicBarrier.new(2)
    results = Concurrent::Array.new
    errors = Concurrent::Array.new

    threads = actors.map do |actor|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          thread_actor = User.find(actor.id)
          thread_account = Account.find(account.id)
          account_user = thread_actor.account_users.find_by!(account: thread_account)
          Current.user = thread_actor
          barrier.wait
          result = Conversations::AutomationTransitionService.new(
            account: thread_account,
            actor: thread_actor,
            account_user: AccountUser.find(account_user.id),
            conversation_display_id: conversation.display_id,
            attributes: {
              action: 'send_to_human_queue',
              idempotency_key: "queue-#{SecureRandom.uuid}"
            }
          ).call
          results << result.status
        rescue StandardError => e
          errors << e
        ensure
          Current.reset
        end
      end
    end
    threads.each(&:join)

    expect(errors).to be_empty
    expect(results).to contain_exactly('accepted', 'duplicate')
    expect(conversation.automation_transitions.count).to eq(1)
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.reload.label_list).to include('aguardando-humano')
  end
end
