require 'rails_helper'

RSpec.describe Conversations::AutomationTransitionService, :non_transactional do
  self.use_transactional_tests = false

  let(:created_account_ids) { [] }

  after { Account.where(id: created_account_ids).destroy_all }

  def return_to_bia(account:, actor:, conversation:, message:, idempotency_key:)
    described_class.new(
      account: account,
      actor: actor,
      account_user: actor.account_users.find_by!(account: account),
      conversation_display_id: conversation.display_id,
      attributes: {
        action: 'return_to_bia',
        idempotency_key: idempotency_key,
        expected_last_message_id: message.id,
        expected_assignee_id: nil
      }
    ).call
  end

  it 'serializes two return requests and creates exactly one transition and note' do
    account = create(:account).tap { |record| record.enable_features!('conversation_return_to_bia') }
    created_account_ids << account.id
    actors = create_list(:user, 2, account: account, role: :administrator)
    conversation = create(
      :conversation,
      account: account,
      label_list: ['aguardando-humano'],
      custom_attributes: {
        'bia_retorno_humano_pendente' => true,
        'bia_automation_state' => 'paused_human',
        'bia_session_generation' => 7
      }
    )
    message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox)
    barrier = Concurrent::CyclicBarrier.new(2)
    results = Concurrent::Array.new
    errors = Concurrent::Array.new
    idempotency_key = "bia-#{SecureRandom.uuid}"

    threads = actors.map do |actor|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          thread_actor = User.find(actor.id)
          thread_account = Account.find(account.id)
          Current.user = thread_actor
          barrier.wait
          result = return_to_bia(
            account: thread_account,
            actor: thread_actor,
            conversation: conversation,
            message: message,
            idempotency_key: idempotency_key
          )
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
    expect(conversation.automation_transitions.where(action: 'return_to_bia').count).to eq(1)
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.reload.custom_attributes['bia_session_generation']).to eq(8)
  end
end
