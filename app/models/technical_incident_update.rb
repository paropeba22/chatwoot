class TechnicalIncidentUpdate < ApplicationRecord
  ORIGINS = %w[ui automation job system].freeze

  belongs_to :account
  belongs_to :technical_incident
  belongs_to :actor, polymorphic: true, optional: true

  validates :origin, inclusion: { in: ORIGINS }
  validates :action, presence: true, length: { maximum: 100 }
  validate :account_consistency

  def readonly?
    persisted?
  end

  private

  def account_consistency
    errors.add(:account, :invalid) if technical_incident && technical_incident.account_id != account_id
  end
end
