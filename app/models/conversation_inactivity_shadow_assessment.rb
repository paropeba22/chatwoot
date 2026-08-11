class ConversationInactivityShadowAssessment < ApplicationRecord
  CLASSIFICATIONS = %w[
    waiting_customer
    waiting_human
    waiting_automation
    likely_completed
    operation_pending
    handoff_pending
    stale_inconsistent
    do_not_touch
    unknown
  ].freeze

  belongs_to :account
  belongs_to :conversation

  validates :classification, inclusion: { in: CLASSIFICATIONS }
  validates :reason_code, :observed_at, presence: true
  validates :confidence, numericality: { in: 0..1 }
  validates :conversation_id, uniqueness: { scope: :account_id }
end
