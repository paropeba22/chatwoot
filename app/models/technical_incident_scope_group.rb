class TechnicalIncidentScopeGroup < ApplicationRecord
  belongs_to :account
  belongs_to :technical_incident, inverse_of: :scope_groups
  has_many :criteria, class_name: 'TechnicalIncidentScopeCriterion', dependent: :destroy, inverse_of: :technical_incident_scope_group

  accepts_nested_attributes_for :criteria, allow_destroy: true

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :account_consistency

  before_validation :inherit_account

  private

  def inherit_account
    self.account ||= technical_incident&.account
    criteria.each { |criterion| criterion.account ||= account }
  end

  def account_consistency
    errors.add(:account, :invalid) if technical_incident && account_id != technical_incident.account_id
  end
end
