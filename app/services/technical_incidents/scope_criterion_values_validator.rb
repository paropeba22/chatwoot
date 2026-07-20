class TechnicalIncidents::ScopeCriterionValuesValidator
  LOCATION_FIELDS = {
    'city_neighborhood' => %w[city neighborhood],
    'city_street' => %w[city street]
  }.freeze

  def initialize(criterion_type:, values:)
    @criterion_type = criterion_type
    @values = values
  end

  def valid?
    return false unless @values.is_a?(Array)
    return @values.empty? if @criterion_type == 'general'

    @values.all? { |value| valid_value?(value) }
  end

  private

  def valid_value?(value)
    return valid_location?(value) if LOCATION_FIELDS.key?(@criterion_type)
    return TechnicalIncident::SERVICE_KEYS.include?(value) if @criterion_type == 'service_specific'
    return valid_postal_code?(value) if @criterion_type == 'postal_code'

    valid_scalar?(value)
  end

  def valid_location?(value)
    return false unless value.is_a?(Hash)

    normalized = value.to_h.stringify_keys
    required = LOCATION_FIELDS.fetch(@criterion_type)
    normalized.keys.sort == required.sort && required.all? { |field| normalized[field].present? }
  end

  def valid_postal_code?(value)
    value.is_a?(String) && TechnicalIncidents::Normalizer.postal_code(value).length == 8
  end

  def valid_scalar?(value)
    value.is_a?(String) && value.present? && value.length <= 200
  end
end
