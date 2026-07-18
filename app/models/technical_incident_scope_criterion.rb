class TechnicalIncidentScopeCriterion < ApplicationRecord
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
    return errors.add(:values, :invalid) unless values.is_a?(Array)
    if general?
      errors.add(:values, :invalid) unless values.empty?
      return
    end

    if city_neighborhood?
      return if values.all? do |value|
        next false unless value.is_a?(Hash)

        normalized = value.to_h.stringify_keys
        normalized.keys.sort == %w[city neighborhood] &&
          normalized['city'].present? && normalized['neighborhood'].present?
      end
    elsif city_street?
      return if values.all? do |value|
        next false unless value.is_a?(Hash)

        normalized = value.to_h.stringify_keys
        normalized.keys.sort == %w[city street] &&
          normalized['city'].present? && normalized['street'].present?
      end
    elsif service_specific?
      return if values.all? { |value| TechnicalIncident::SERVICE_KEYS.include?(value) }
    elsif postal_code?
      return if values.all? do |value|
        value.is_a?(String) && TechnicalIncidents::Normalizer.postal_code(value).length == 8
      end
    elsif values.all? { |value| value.is_a?(String) && value.present? && value.length <= 200 }
      return
    end

    errors.add(:values, :invalid)
  end
end
