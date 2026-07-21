require 'rails_helper'

RSpec.describe TechnicalIncidents::Configuration do
  it 'defaults every automation and delivery gate to disabled' do
    with_modified_env(
      TECHNICAL_INCIDENTS_AUTOMATION_MODE: nil,
      TECHNICAL_INCIDENTS_OUTBOX_ENABLED: nil,
      TECHNICAL_INCIDENTS_DELIVERY_ENABLED: nil,
      TECHNICAL_INCIDENTS_API_INBOX_DELIVERY_ENABLED: nil
    ) do
      expect(described_class.automation_mode).to eq('disabled')
      expect(described_class.outbox_enabled?).to be(false)
      expect(described_class.delivery_enabled?).to be(false)
      expect(described_class.api_inbox_delivery_enabled?).to be(false)
    end
  end

  it 'never lets a request elevate the server mode' do
    with_modified_env TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'shadow' do
      expect(described_class.effective_mode('active')).to eq('shadow')
    end
    with_modified_env TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'active' do
      expect(described_class.effective_mode('shadow')).to eq('shadow')
      expect(described_class.effective_mode('active')).to eq('active')
    end
  end

  it 'fails closed for an invalid configured mode or threshold' do
    with_modified_env(
      TECHNICAL_INCIDENTS_AUTOMATION_MODE: 'root',
      TECHNICAL_INCIDENTS_HIGH_CONFIDENCE: 'invalid'
    ) do
      expect(described_class.automation_mode).to eq('disabled')
      expect(described_class.high_confidence).to eq(0.85)
    end
  end
end
