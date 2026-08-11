require 'rails_helper'

RSpec.describe Conversations::BiaSession::ResetContextService, :non_transactional do
  self.use_transactional_tests = false

  let(:created_account_ids) { [] }
  let(:created_conversation_ids) { [] }

  after do
    Conversation.where(id: created_conversation_ids).destroy_all
    Account.where(id: created_account_ids).destroy_all
  end

  def run_concurrent_resets(context)
    results = Concurrent::Array.new
    errors = Concurrent::Array.new
    threads = context.fetch(:actors).map do |actor|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          reset_in_thread(context, actor, results)
        rescue StandardError => e
          errors << e
        ensure
          Current.reset
        end
      end
    end
    threads.each(&:join)
    [results, errors]
  end

  def reset_in_thread(context, actor, results)
    thread_account = Account.find(context.fetch(:account).id)
    thread_actor = User.find(actor.id)
    context.fetch(:barrier).wait
    result = described_class.new(
      account: thread_account,
      actor: thread_actor,
      account_user: thread_actor.account_users.find_by!(account: thread_account),
      conversation_display_id: context.fetch(:conversation).display_id,
      attributes: {
        expected_generation: 5,
        source_message_id: context.fetch(:message).id,
        idempotency_key: context.fetch(:idempotency_key),
        reset_profile: 'bia_session_v1'
      }
    ).call
    results << result.status
  end

  it 'serializes two PostgreSQL threads so exactly one applies and one replays' do
    account = create(:account).tap { |record| record.enable_features!('conversation_return_to_bia') }
    created_account_ids << account.id
    actors = create_list(:user, 2, account: account, role: :administrator)
    conversation = create(
      :conversation,
      account: account,
      status: :open,
      label_list: ['bot-bia'],
      custom_attributes: {
        'bia_automation_state' => 'active',
        'bia_session_generation' => 5,
        'bia_resume_after_message_id' => 0,
        'bia_context_reset_required' => true,
        'bia_retorno_humano_pendente' => false,
        'concurrent_attribute' => 'preserved'
      }
    )
    created_conversation_ids << conversation.id
    message = create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)
    barrier = Concurrent::CyclicBarrier.new(2)
    idempotency_key = "bia-reset-#{SecureRandom.uuid}"
    results, errors = run_concurrent_resets(
      account: account,
      actors: actors,
      conversation: conversation,
      message: message,
      idempotency_key: idempotency_key,
      barrier: barrier
    )

    expect(errors).to be_empty
    expect(results).to contain_exactly('accepted', 'duplicate')
    expect(conversation.bia_session_operations.where(operation: 'reset_context').count).to eq(1)
    expect(conversation.reload.custom_attributes).to include(
      'bia_session_generation' => 5,
      'bia_context_reset_required' => false,
      'concurrent_attribute' => 'preserved'
    )
  end
end
