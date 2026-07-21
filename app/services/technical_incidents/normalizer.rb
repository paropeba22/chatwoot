class TechnicalIncidents::Normalizer
  def self.text(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').squish.first(200)
  end

  def self.identifier(value)
    value.to_s.strip.first(200)
  end

  def self.postal_code(value)
    value.to_s.gsub(/\D/, '')[0, 8]
  end

  def self.contract(raw)
    data = contract_data(raw)
    location = data.delete('location').to_h.stringify_keys

    contract_identity(data).merge(
      'location' => normalized_location(data, location)
    )
  end

  def self.contract_data(raw)
    raw.to_h.stringify_keys.slice(
      'contract_id', 'status', 'pop_id', 'pop_name', 'service_group', 'connection_type',
      'state', 'city', 'neighborhood', 'postal_code', 'street', 'number', 'location'
    )
  end

  def self.contract_identity(data)
    {
      'contract_id' => identifier(data['contract_id']),
      'status' => data['status'].to_s,
      'pop_id' => identifier(data['pop_id']),
      'pop_name' => TechnicalIncidents::TextSanitizer.call(data['pop_name'])&.first(200),
      'service_group' => text(data['service_group']),
      'connection_type' => text(data['connection_type'])
    }
  end

  def self.normalized_location(data, location)
    {
      'state' => text(data['state'] || location['state']),
      'city' => text(data['city'] || location['city']),
      'neighborhood' => text(data['neighborhood'] || location['neighborhood']),
      'postal_code' => postal_code(data['postal_code'] || location['postal_code']),
      'street' => text(data['street'] || location['street']),
      'number' => text(data['number'] || location['number'])
    }
  end

  private_class_method :contract_data, :contract_identity, :normalized_location
end
