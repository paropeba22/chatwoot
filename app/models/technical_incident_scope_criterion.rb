class TechnicalIncidentScopeCriterion < ApplicationRecord
  self.table_name = 'technical_incident_scope_criteria'

  TYPES = %w[general service_specific contract_id pop_id postal_code city_neighborhood city_street].freeze
  OPERATORS = %w[in].freeze

  belongs_to :account
  belongs_to :technical_incident_scope_group, inverse_of: :criteria

  validates :criterion_type, inclusion: { in: TYPES }, uniqueness: { scope: :technical_incident_scope_group_id }
  validates :operator, inclusion: { in: OPERATORS }
  validates :values, presence: true, unless: :general?
  validate :values_shape
  validate :account_consistency

  before_validation :inherit_account

  TYPES.each do |type|
    define_method("#{type}?") { criterion_type == type }
  end

  private

  def inherit_account
    self.account ||= technical_incident_scope_group&.account
  end

  def account_consistency
    group = technical_incident_scope_group
    errors.add(:account, :invalid) if group && account_id != group.account_id
  end

  def values_shape
    validator = TechnicalIncidents::ScopeCriterionValuesValidator.new(criterion_type: criterion_type, values: values)
    errors.add(:values, :invalid) unless validator.valid?
  end
end
