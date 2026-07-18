class TechnicalIncidentDelivery < ApplicationRecord
  STATES = %w[
    reserved message_created delivery_queued delivered handoff_completed failed_retryable failed_terminal
  ].freeze
  DELIVERY_KINDS = %w[initial update reopening].freeze

  belongs_to :account
  belongs_to :technical_incident
  belongs_to :technical_incident_evaluation
  belongs_to :technical_incident_conversation_link, optional: true
  belongs_to :conversation
  belongs_to :message, optional: true

  validates :idempotency_key, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :delivery_kind, inclusion: { in: DELIVERY_KINDS }
  validate :account_consistency

  scope :retryable, -> { where(state: 'failed_retryable').where('attempts < 5') }

  private

  def account_consistency
    errors.add(:technical_incident, :invalid) if technical_incident && technical_incident.account_id != account_id
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
  end
end
