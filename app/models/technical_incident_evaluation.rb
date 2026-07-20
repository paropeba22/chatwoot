class TechnicalIncidentEvaluation < ApplicationRecord
  STATUSES = %w[
    no_candidate general_match localized_candidate needs_document needs_contract_selection matched
    ambiguous expired fallback stale duplicate accepted
  ].freeze
  MODES = %w[shadow active].freeze
  FEEDBACK_TYPES = %w[correct_match false_positive false_negative wrong_contract wrong_category duplicate_message other].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :technical_incident, optional: true
  belongs_to :agent_bot, optional: true
  belongs_to :feedback_by, class_name: 'User', optional: true

  has_many :deliveries, class_name: 'TechnicalIncidentDelivery', dependent: :restrict_with_error

  validates :opaque_id, :request_id, :contract_version, presence: true
  validates :opaque_id, uniqueness: true
  validates :request_id, uniqueness: { scope: :account_id }
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :feedback, inclusion: { in: FEEDBACK_TYPES }, allow_nil: true
  validate :account_consistency

  before_validation :ensure_opaque_id, on: :create

  def stale?
    expires_at <= Time.current
  end

  private

  def ensure_opaque_id
    self.opaque_id ||= SecureRandom.urlsafe_base64(32)
  end

  def account_consistency
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
    errors.add(:technical_incident, :invalid) if technical_incident && technical_incident.account_id != account_id
    errors.add(:agent_bot, :invalid) if agent_bot && agent_bot.account_id.present? && agent_bot.account_id != account_id
    if feedback_by && !account.account_users.exists?(user_id: feedback_by.id)
      errors.add(:feedback_by, :invalid)
    end
  end
end
