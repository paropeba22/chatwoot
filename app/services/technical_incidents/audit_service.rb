class TechnicalIncidents::AuditService
  SENSITIVE_KEYS = %w[cpf cnpj phone phone_number password senha login mac address full_address].freeze

  def self.record!(incident:, action:, origin:, **context)
    incident.updates.create!(
      account: incident.account,
      actor: context[:actor],
      origin: origin,
      action: action,
      changeset: sanitize(context.fetch(:changeset, {})),
      request_id: context[:request_id]
    )
  end

  def self.sanitize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, child), result|
        result[key] = sanitize(child) unless SENSITIVE_KEYS.include?(key.to_s.downcase)
      end
    when Array
      value.map { |child| sanitize(child) }
    else
      value
    end
  end
end
