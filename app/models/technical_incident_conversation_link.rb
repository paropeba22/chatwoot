class TechnicalIncidentConversationLink < ApplicationRecord
  belongs_to :account
  belongs_to :technical_incident, counter_cache: :conversation_links_count
  belongs_to :conversation
  belongs_to :technical_incident_evaluation, optional: true

  validates :notification_version, numericality: { only_integer: true, greater_than: 0 }
  validate :account_consistency

  private

  def account_consistency
    errors.add(:technical_incident, :invalid) if technical_incident && technical_incident.account_id != account_id
    errors.add(:conversation, :invalid) if conversation && conversation.account_id != account_id
  end
end
