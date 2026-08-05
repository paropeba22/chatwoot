class Conversations::InactivityShadowJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 200
  LOCK_NAMESPACE = 1_904_827_311

  def perform(account_id, after_id: 0, batch_size: BATCH_SIZE)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('conversation_inactivity_shadow')

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_acquired = acquire_lock(connection, account.id)
      return unless lock_acquired

      process_batch(account, after_id, batch_size)
    ensure
      release_lock(connection, account.id) if lock_acquired
    end
  end

  private

  def process_batch(account, after_id, batch_size)
    conversations = account.conversations.where('id > ?', after_id).order(:id).limit(batch_size).to_a
    conversations.each { |conversation| persist_assessment(account, conversation) }
    schedule_next(account, conversations, batch_size)
  end

  def persist_assessment(account, conversation)
    result = Conversations::InactivityShadowClassifier.new(conversation).call
    attributes = result.to_h.merge(
      account_id: account.id,
      conversation_id: conversation.id,
      observed_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    )
    ConversationInactivityShadowAssessment.upsert(
      attributes,
      unique_by: :idx_inactivity_shadow_account_conversation
    )
  end

  def schedule_next(account, conversations, batch_size)
    return unless conversations.size == batch_size

    self.class.perform_later(account.id, after_id: conversations.last.id, batch_size: batch_size)
  end

  def acquire_lock(connection, account_id)
    ActiveModel::Type::Boolean.new.cast(
      connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_NAMESPACE}, #{Integer(account_id)})")
    )
  end

  def release_lock(connection, account_id)
    connection.select_value("SELECT pg_advisory_unlock(#{LOCK_NAMESPACE}, #{Integer(account_id)})")
  end
end
