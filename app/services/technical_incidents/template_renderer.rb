class TechnicalIncidents::TemplateRenderer
  ALLOWED_VARIABLES = %w[estimated_resolution_at affected_service incident_title].freeze
  VARIABLE_PATTERN = /\{\{\s*([a-z_]+)\s*\}\}/.freeze
  ANY_OUTPUT_PATTERN = /\{\{.*?\}\}/m.freeze
  TAG_PATTERN = /\{%.*?%\}/m.freeze

  class InvalidTemplate < StandardError; end

  def self.validate!(incident)
    source = incident.customer_message.to_s
    raise InvalidTemplate, 'liquid_tags_not_allowed' if source.match?(TAG_PATTERN)

    outputs = source.scan(ANY_OUTPUT_PATTERN)
    raise InvalidTemplate, 'template_expression_not_allowed' unless outputs.all? { |output| output.match?(/\A#{VARIABLE_PATTERN}\z/) }

    variables = source.scan(VARIABLE_PATTERN).flatten
    unknown = variables - ALLOWED_VARIABLES
    raise InvalidTemplate, "unknown_variables:#{unknown.join(',')}" if unknown.any?

    values = template_values(incident)
    missing = variables.uniq.select { |variable| values[variable].blank? }
    raise InvalidTemplate, "missing_values:#{missing.join(',')}" if missing.any?
  end

  def self.render(incident)
    validate!(incident)
    values = template_values(incident)
    incident.customer_message.to_s.gsub(VARIABLE_PATTERN) { values[Regexp.last_match(1)].to_s }
  end

  def self.template_values(incident)
    {
      'estimated_resolution_at' => incident.estimated_resolution_at&.iso8601,
      'affected_service' => incident.affected_services.one? ? incident.affected_services.first : nil,
      'incident_title' => incident.title
    }
  end
end
