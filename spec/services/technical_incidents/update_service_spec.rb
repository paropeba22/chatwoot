require 'rails_helper'

RSpec.describe TechnicalIncidents::UpdateService do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account) }
  let(:incident) do
    record = create(:technical_incident, :active, account: account)
    group = create(:technical_incident_scope_group, account: account, technical_incident: record)
    create(
      :technical_incident_scope_criterion,
      account: account,
      technical_incident_scope_group: group,
      criterion_type: 'general',
      values: []
    )
    record
  end

  it 'increments notification_version for message, ETA, service or scope decision changes' do
    expect do
      described_class.new(
        incident: incident,
        attributes: { customer_message: 'Nova mensagem literal.' },
        actor: actor
      ).call
    end.to change(incident, :notification_version).by(1)

    expect do
      described_class.new(
        incident: incident,
        attributes: { affected_services: ['dns'] },
        actor: actor
      ).call
    end.to change(incident, :notification_version).by(1)
  end

  it 'does not increment notification_version for an internal-only note' do
    expect do
      described_class.new(
        incident: incident,
        attributes: { internal_note: 'Contexto interno atualizado.' },
        actor: actor
      ).call
    end.not_to change(incident, :notification_version)
  end

  it 'does not increment notification_version for a no-op update' do
    expect do
      described_class.new(
        incident: incident,
        attributes: { affected_services: incident.affected_services },
        actor: actor
      ).call
    end.not_to change(incident, :notification_version)
  end

  it 'raises a stale object error for two editors using the same lock version' do
    first_copy = incident
    second_copy = TechnicalIncident.find(incident.id)
    stale_version = incident.lock_version

    described_class.new(
      incident: first_copy,
      attributes: { title: 'Primeira edição', lock_version: stale_version },
      actor: actor
    ).call

    expect do
      described_class.new(
        incident: second_copy,
        attributes: { title: 'Edição concorrente', lock_version: stale_version },
        actor: actor
      ).call
    end.to raise_error(ActiveRecord::StaleObjectError)
  end
end
