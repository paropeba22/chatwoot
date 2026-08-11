require 'rails_helper'

RSpec.describe TechnicalIncidents::FormMetadataPresenter do
  subject(:metadata) { described_class.new.as_json }

  it 'derives every catalog from the same allowlists enforced by the domain' do
    expect(metadata.fetch(:incident_types).pluck(:value)).to eq(TechnicalIncident::INCIDENT_TYPES)
    expect(metadata.fetch(:severities).pluck(:value)).to eq(TechnicalIncident::SEVERITIES)
    expect(metadata.fetch(:problem_types).pluck(:value)).to eq(TechnicalIncident::PROBLEM_TYPES)
    expect(metadata.fetch(:affected_services).pluck(:value)).to eq(TechnicalIncident::SERVICE_KEYS)
    expect(metadata.fetch(:actions).pluck(:value)).to eq(TechnicalIncident::ACTIONS)
    expect(metadata.fetch(:scope_fields).pluck(:value)).to eq(TechnicalIncidentScopeCriterion::TYPES)
  end

  it 'describes value shapes and compatible operators without exposing customer data' do
    fields = metadata.fetch(:scope_fields).index_by { |field| field.fetch(:value) }

    expect(fields.fetch('general')).to include(value_type: 'none', required: false)
    expect(fields.fetch('service_specific')).to include(
      value_type: 'catalog_multi_select',
      allowed_operators: ['in']
    )
    expect(fields.fetch('service_specific').fetch(:available_values).pluck(:value)).to eq(TechnicalIncident::SERVICE_KEYS)
    expect(fields.fetch('city_street')).to include(value_fields: %w[city street])
    expect(metadata.to_json).not_to match(/cpf|phone|password|token/i)
  end
end
