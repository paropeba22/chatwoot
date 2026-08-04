class TechnicalIncidents::FormMetadataPresenter
  SCOPE_FIELDS = {
    'general' => { value_type: 'none', required: false, multiple: false },
    'service_specific' => { value_type: 'catalog_multi_select', required: true, multiple: true },
    'contract_id' => { value_type: 'string_list', required: true, multiple: true },
    'pop_id' => { value_type: 'string_list', required: true, multiple: true },
    'postal_code' => { value_type: 'string_list', required: true, multiple: true },
    'city_neighborhood' => {
      value_type: 'location_pairs', required: true, multiple: true, value_fields: %w[city neighborhood]
    },
    'city_street' => {
      value_type: 'location_pairs', required: true, multiple: true, value_fields: %w[city street]
    }
  }.freeze

  def as_json(*)
    {
      metadata_version: 1,
      incident_types: catalog(TechnicalIncident::INCIDENT_TYPES, 'INCIDENT_TYPES'),
      statuses: catalog(TechnicalIncident::STATUSES, 'STATUSES'),
      severities: catalog(TechnicalIncident::SEVERITIES, 'SEVERITIES'),
      problem_types: catalog(TechnicalIncident::PROBLEM_TYPES, 'PROBLEM_TYPES'),
      affected_services: catalog(TechnicalIncident::SERVICE_KEYS, 'SERVICES'),
      actions: action_catalog,
      scope_fields: scope_field_catalog,
      scope_operators: catalog(TechnicalIncidentScopeCriterion::OPERATORS, 'SCOPE_OPERATORS'),
      template_variables: TechnicalIncidents::TemplateRenderer::ALLOWED_VARIABLES
    }
  end

  private

  def catalog(values, group)
    values.map { |value| option(value, group) }
  end

  def action_catalog
    catalog(TechnicalIncident::ACTIONS, 'ACTIONS').map do |entry|
      entry.merge(description_key: "TECHNICAL_INCIDENTS.CATALOG.ACTION_DESCRIPTIONS.#{entry[:value].upcase}")
    end
  end

  def scope_field_catalog
    TechnicalIncidentScopeCriterion::TYPES.map do |value|
      config = SCOPE_FIELDS.fetch(value)
      option(value, 'SCOPE_FIELDS').merge(
        allowed_operators: TechnicalIncidentScopeCriterion::OPERATORS,
        available_values: value == 'service_specific' ? catalog(TechnicalIncident::SERVICE_KEYS, 'SERVICES') : [],
        **config
      )
    end
  end

  def option(value, group)
    {
      value: value,
      label: value.humanize,
      label_key: "TECHNICAL_INCIDENTS.CATALOG.#{group}.#{value.upcase}"
    }
  end
end
