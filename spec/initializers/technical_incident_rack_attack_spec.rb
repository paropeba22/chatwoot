require 'rails_helper'

RSpec.describe Rack::Attack do
  it 'normalizes opaque identifiers so token and IP throttles cannot be bypassed by varying IDs' do
    expect(described_class.technical_incident_endpoint('/api/v1/technical_incident_checks/one/match'))
      .to eq('/api/v1/technical_incident_checks/:id/match')
    expect(described_class.technical_incident_endpoint('/api/v1/technical_incident_checks/two/commit'))
      .to eq('/api/v1/technical_incident_checks/:id/commit')
    expect(described_class.technical_incident_endpoint('/api/v1/technical_incident_evaluations/three/feedback'))
      .to eq('/api/v1/technical_incident_evaluations/:id/feedback')
  end
end
