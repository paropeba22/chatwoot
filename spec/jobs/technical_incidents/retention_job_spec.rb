require 'rails_helper'

RSpec.describe TechnicalIncidents::RetentionJob do
  it 'anonymizes evaluation payloads after 180 days without breaking operational links' do
    account = create(:account)
    evaluation = create(
      :technical_incident_evaluation,
      account: account,
      classification: { problem_type: 'internet_connectivity' },
      sanitized_contracts: [{ contract_id: 'CTR-100', city: 'Recife' }],
      selected_contract: { contract_id: 'CTR-100' },
      feedback_note: 'Contains operational context',
      created_at: 181.days.ago
    )

    described_class.perform_now

    expect(evaluation.reload).to have_attributes(
      classification: {},
      sanitized_contracts: [],
      selected_contract: {},
      feedback_note: nil,
      source_message_id: nil
    )
  end

  it 'keeps audit updates for five years and purges older records' do
    incident = create(:technical_incident)
    old_update = incident.updates.create!(
      account: incident.account,
      origin: 'system',
      action: 'retention.fixture',
      created_at: 5.years.ago - 1.day
    )
    recent_update = incident.updates.create!(
      account: incident.account,
      origin: 'system',
      action: 'retention.recent',
      created_at: 5.years.ago + 1.day
    )

    described_class.perform_now

    expect(TechnicalIncidentUpdate.exists?(old_update.id)).to be(false)
    expect(TechnicalIncidentUpdate.exists?(recent_update.id)).to be(true)
  end
end
