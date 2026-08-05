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
    snapshots = message_snapshots(conversations)
    conversations.each { |conversation| persist_assessment(account, conversation, snapshots.fetch(conversation.id)) }
    schedule_next(account, conversations, batch_size)
  end

  def persist_assessment(account, conversation, message_snapshot)
    result = Conversations::InactivityShadowClassifier.new(conversation, message_snapshot: message_snapshot).call
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

  def message_snapshots(conversations)
    conversation_ids = conversations.map(&:id)
    public_messages = Message.where(conversation_id: conversation_ids, private: false).where.not(message_type: :activity)
    latest = latest_by_conversation(public_messages)
    incoming = latest_by_conversation(public_messages.incoming)
    outgoing = latest_by_conversation(public_messages.outgoing)

    conversation_ids.index_with do |conversation_id|
      {
        last_public_message: latest[conversation_id],
        last_public_incoming: incoming[conversation_id],
        last_public_outgoing: outgoing[conversation_id]
      }
    end
  end

  def latest_by_conversation(scope)
    scope
      .select('DISTINCT ON (messages.conversation_id) messages.*')
      .reorder('messages.conversation_id, messages.id DESC')
      .index_by(&:conversation_id)
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
