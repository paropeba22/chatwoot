class ConversationAutomationTransition < ApplicationRecord
  ACTIONS = %w[send_to_human_queue].freeze
  STATUSES = %w[completed].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :audit_message, class_name: 'Message', optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :reason_code, presence: true, length: { maximum: 100 }
  validates :idempotency_key,
            presence: true,
            length: { minimum: 8, maximum: 128 },
            format: { with: /\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/ },
            uniqueness: { scope: %i[account_id conversation_id action] }
  validates :completed_at, presence: true
  validate :account_consistency

  private

  def account_consistency
    return if account.blank?

    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
    return if actor.blank? || account.account_users.exists?(user_id: actor_id)

    errors.add(:actor, :invalid)
  end
end
