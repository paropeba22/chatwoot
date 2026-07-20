class TechnicalIncidentConversationLink < ApplicationRecord
  belongs_to :account
  belongs_to :technical_incident, counter_cache: :conversation_links_count
  belongs_to :conversation
  belongs_to :technical_incident_evaluation, optional: true

  validates :notification_version, numericality: { only_integer: true, greater_than: 0 }
  validate :account_consistency

  private

  def account_consistency
    validate_account(:technical_incident)
    validate_account(:conversation)
    validate_account(:technical_incident_evaluation)
  end

  def validate_account(association)
    record = public_send(association)
    errors.add(association, :invalid) if record && record.account_id != account_id
  end
end
