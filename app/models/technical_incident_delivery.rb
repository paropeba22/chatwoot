class TechnicalIncidentDelivery < ApplicationRecord
  STATES = %w[
    reserved message_created delivery_queued delivered handoff_completed failed_retryable failed_terminal
  ].freeze
  DELIVERY_KINDS = %w[initial update reopening].freeze
  OUTBOX_STATES = %w[pending processing retry completed failed_terminal].freeze
  MESSAGE_STATES = %w[pending not_required created failed_retryable failed_terminal].freeze
  TRANSPORT_STATES = %w[pending not_required queued delivered failed_retryable failed_terminal].freeze
  STEP_STATES = %w[pending not_required completed failed_retryable failed_terminal].freeze

  belongs_to :account
  belongs_to :technical_incident
  belongs_to :technical_incident_evaluation
  belongs_to :technical_incident_conversation_link, optional: true
  belongs_to :conversation
  belongs_to :message, optional: true

  validates :idempotency_key, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :delivery_kind, inclusion: { in: DELIVERY_KINDS }
  validates :outbox_state, inclusion: { in: OUTBOX_STATES }
  validates :message_state, inclusion: { in: MESSAGE_STATES }
  validates :transport_state, inclusion: { in: TRANSPORT_STATES }
  validates :link_state, :label_state, :note_state, :handoff_state, :audit_state, inclusion: { in: STEP_STATES }
  validate :account_consistency

  scope :outbox_ready, lambda {
    where(outbox_state: %w[pending retry])
      .where('next_retry_at IS NULL OR next_retry_at <= ?', Time.current)
      .where('attempts < ?', TechnicalIncidents::Configuration.max_delivery_attempts)
  }
  scope :outbox_stuck, lambda {
    where(outbox_state: 'processing').where('locked_at < ?', TechnicalIncidents::Configuration.outbox_lease.ago)
  }

  private

  def account_consistency
    errors.add(:technical_incident, :invalid) if technical_incident && technical_incident.account_id != account_id
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
    if technical_incident_evaluation && technical_incident_evaluation.account_id != account_id
      errors.add(:technical_incident_evaluation, :invalid)
    end
    if technical_incident_conversation_link && technical_incident_conversation_link.account_id != account_id
      errors.add(:technical_incident_conversation_link, :invalid)
    end
    errors.add(:message, :invalid) if message && (message.account_id != account_id || message.conversation_id != conversation_id)
  end
end
