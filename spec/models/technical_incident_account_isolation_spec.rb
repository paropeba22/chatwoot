require 'rails_helper'

RSpec.describe 'Technical incident account isolation' do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:incident) { create(:technical_incident, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:foreign_conversation) { create(:conversation, account: other_account) }

  it 'rejects cross-account evaluations' do
    evaluation = build(
      :technical_incident_evaluation,
      account: account,
      conversation: foreign_conversation,
      technical_incident: incident
    )

    expect(evaluation).not_to be_valid
    expect(evaluation.errors).to include(:conversation)
  end

  it 'rejects cross-account conversation links' do
    link = TechnicalIncidentConversationLink.new(
      account: account,
      technical_incident: incident,
      conversation: foreign_conversation,
      notification_version: 1
    )

    expect(link).not_to be_valid
    expect(link.errors).to include(:conversation)
  end

  it 'rejects cross-account deliveries even when identifiers are supplied directly' do
    evaluation = create(
      :technical_incident_evaluation,
      account: account,
      conversation: conversation,
      technical_incident: incident
    )
    delivery = TechnicalIncidentDelivery.new(
      account: account,
      technical_incident: incident,
      technical_incident_evaluation: evaluation,
      conversation: foreign_conversation,
      idempotency_key: SecureRandom.uuid,
      delivery_kind: 'initial',
      state: 'reserved',
      outbox_state: 'pending',
      message_state: 'pending',
      transport_state: 'pending',
      link_state: 'pending',
      label_state: 'pending',
      note_state: 'pending',
      handoff_state: 'pending',
      audit_state: 'pending'
    )

    expect(delivery).not_to be_valid
    expect(delivery.errors).to include(:conversation)
  end
end
