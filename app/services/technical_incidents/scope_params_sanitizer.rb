class TechnicalIncidents::ScopeParamsSanitizer
  class << self
    def call(raw_groups)
      collection(raw_groups).first(50).map { |group| sanitize_group(group) }
    end

    private

    def sanitize_group(raw_group)
      group = parameter_hash(raw_group)
      group.slice('id', 'position', '_destroy').merge(
        'criteria_attributes' => collection(group['criteria_attributes']).first(20).map do |criterion|
          sanitize_criterion(criterion)
        end
      )
    end

    def sanitize_criterion(raw_criterion)
      criterion = parameter_hash(raw_criterion)
      criterion.slice('id', 'criterion_type', 'operator', '_destroy').merge(
        'values' => sanitize_values(criterion['values'])
      )
    end

    def sanitize_values(raw_values)
      collection(raw_values).first(200).map { |value| sanitize_value(value) }
    end

    def sanitize_value(value)
      return value.to_s.first(200) if value.is_a?(String) || !value.respond_to?(:to_h)

      parameter_hash(value).slice('city', 'neighborhood', 'street')
    end

    def parameter_hash(value)
      source = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      source.stringify_keys
    end

    def collection(value)
      return [] if value.nil?
      return value.values if value.respond_to?(:values) && !value.is_a?(Array)

      Array(value)
    end
  end
end
