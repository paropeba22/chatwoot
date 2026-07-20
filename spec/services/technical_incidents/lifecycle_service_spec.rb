require 'rails_helper'

RSpec.describe TechnicalIncidents::LifecycleService do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:incident) do
    record = build(:technical_incident, account: account)
    group = record.scope_groups.build(account: account)
    group.criteria.build(account: account, criterion_type: 'general', values: [])
    record.tap(&:save!)
  end

  it 'uses the six-hour default when first activated' do
    travel_to(Time.zone.parse('2026-07-17 12:00:00')) do
      incident.update!(expires_at: nil)
      described_class.new(incident: incident, actor: nil).transition!('active')

      expect(incident.expires_at).to eq(6.hours.from_now)
    end
  end

  it 'does not allow monitoring incidents to intercept' do
    described_class.new(incident: incident, actor: nil).transition!('active')
    described_class.new(incident: incident, actor: nil).transition!('monitoring')

    expect(TechnicalIncident.intercepting).not_to include(incident)
  end

  it 'requires a new future expiration and increments the version on reopening' do
    described_class.new(incident: incident, actor: nil).transition!('active')
    described_class.new(incident: incident, actor: nil).transition!('resolved')

    expect do
      described_class.new(incident: incident, actor: nil).transition!('active')
    end.to raise_error(described_class::InvalidTransition, 'reopening_requires_new_expiration')

    expect do
      described_class.new(incident: incident, actor: nil).transition!('active', expires_at: 4.hours.from_now)
    end.to change(incident, :notification_version).by(1)
    expect(incident.starts_at).to be_within(1.second).of(Time.current)
  end

  it 'does not activate an incident before its start time' do
    incident.update!(starts_at: 1.hour.from_now, expires_at: 7.hours.from_now)

    expect do
      described_class.new(incident: incident, actor: nil).transition!('active')
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects activation when a template variable has no value' do
    incident.update!(customer_message: 'Previsão: {{estimated_resolution_at}}', estimated_resolution_at: nil)

    expect do
      described_class.new(incident: incident, actor: nil).transition!('active')
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'revalidates the transition after acquiring the lock' do
    first = described_class.new(incident: incident, actor: nil)
    second = described_class.new(incident: incident, actor: nil)

    first.transition!('active')
    expect { second.transition!('active') }.to raise_error(described_class::InvalidTransition)
  end

  it 'does not reactivate monitoring with an expired window' do
    described_class.new(incident: incident, actor: nil).transition!('active')
    described_class.new(incident: incident, actor: nil).transition!('monitoring')
    incident.update_columns(expires_at: 1.minute.ago)

    expect do
      described_class.new(incident: incident, actor: nil).transition!('active')
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
