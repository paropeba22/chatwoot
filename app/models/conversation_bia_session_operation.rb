class ConversationBiaSessionOperation < ApplicationRecord
  OPERATIONS = %w[reset_context create_message].freeze
  STATUSES = %w[completed].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :source_message, class_name: 'Message', inverse_of: :bia_session_source_operations
  belongs_to :result_message, class_name: 'Message', optional: true, inverse_of: :bia_session_result_operations

  validates :operation, inclusion: { in: OPERATIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :reason_code, presence: true, length: { maximum: 100 }
  validates :session_generation, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :idempotency_key,
            presence: true,
            length: { minimum: 8, maximum: 128 },
            format: { with: /\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/ },
            uniqueness: { scope: %i[account_id conversation_id operation] }
  validates :completed_at, presence: true
  validate :account_consistency
  validate :message_consistency

  private

  def account_consistency
    return if account.blank?

    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
    return if actor.blank? || account.account_users.exists?(user_id: actor_id)

    errors.add(:actor, :invalid)
  end

  def message_consistency
    errors.add(:source_message, :invalid) if source_message && source_message.conversation_id != conversation_id
    errors.add(:result_message, :invalid) if result_message && result_message.conversation_id != conversation_id
  end
end
