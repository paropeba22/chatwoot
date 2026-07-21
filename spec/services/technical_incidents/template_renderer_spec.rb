require 'rails_helper'

RSpec.describe TechnicalIncidents::TemplateRenderer do
  let(:incident) { build(:technical_incident, customer_message: 'Previsão {{estimated_resolution_at}}') }

  it 'renders only the controlled plain-text allowlist' do
    expect(described_class.render(incident)).to eq("Previsão #{incident.estimated_resolution_at.iso8601}")
  end

  it 'rejects unknown outputs, filters, tags, loops, includes and nested expressions' do
    [
      '{{unknown}}',
      '{{ incident_title | upcase }}',
      '{% if incident_title %}x{% endif %}',
      '{% for item in items %}x{% endfor %}',
      '{% include "secret" %}',
      '{{ {{incident_title}} }}'
    ].each do |template|
      incident.customer_message = template
      expect { described_class.validate!(incident) }.to raise_error(described_class::InvalidTemplate)
    end
  end
end
