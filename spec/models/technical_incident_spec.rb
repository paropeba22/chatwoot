require 'rails_helper'

RSpec.describe TechnicalIncident do
  let(:account) { create(:account) }

  def incident_with_scope(status: 'draft', criterion_type: 'general', values: [])
    incident = build(:technical_incident, account: account, status: status)
    group = incident.scope_groups.build(account: account)
    group.criteria.build(account: account, criterion_type: criterion_type, values: values)
    incident
  end

  it 'allows only the controlled problem and service taxonomies' do
    incident = incident_with_scope
    incident.problem_types = ['invented_problem']
    incident.affected_services = ['invented_service']

    expect(incident).not_to be_valid
    expect(incident.errors).to include(:problem_types, :affected_services)
  end

  it 'requires at least one affected service' do
    incident = incident_with_scope
    incident.affected_services = []

    expect(incident).not_to be_valid
    expect(incident.errors).to include(:affected_services)
  end

  it 'enforces the maximum seven-day window' do
    incident = incident_with_scope
    incident.expires_at = incident.starts_at + 7.days + 1.second

    expect(incident).not_to be_valid
    expect(incident.errors).to include(:expires_at)
  end

  it 'rejects review after expiration and restoration estimates before start' do
    incident = incident_with_scope
    incident.review_at = incident.expires_at + 1.minute
    incident.estimated_resolution_at = incident.starts_at - 1.minute

    expect(incident).not_to be_valid
    expect(incident.errors).to include(:review_at, :estimated_resolution_at)
  end

  it 'does not allow the UI validator to persist an incomplete draft scope or message' do
    incident = build(:technical_incident, account: account, customer_message: '')
    incident.scope_groups.build(account: account)

    expect do
      TechnicalIncidents::IncidentValidator.new(incident).validate!
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(incident.errors).to include(:scope_groups, :customer_message)
  end

  it 'sanitizes unsafe control characters while preserving plain text' do
    incident = incident_with_scope
    incident.title = "Falha\u0000 <script>alert(1)</script>"
    incident.valid?

    expect(incident.title).to eq('Falha <script>alert(1)</script>')
  end

  it 'treats a general plus service group as general but a contract group as localized' do
    general = incident_with_scope
    general.scope_groups.first.criteria.build(
      account: account,
      criterion_type: 'service_specific',
      values: ['internet']
    )
    localized = incident_with_scope(criterion_type: 'contract_id', values: ['CTR-1'])

    expect(general).to be_general_scope
    expect(localized).not_to be_general_scope
  end

  it 'rejects free-form service criteria and malformed postal codes' do
    service = incident_with_scope(criterion_type: 'service_specific', values: ['invented_service'])
    postal = incident_with_scope(criterion_type: 'postal_code', values: ['5000'])

    expect(service).not_to be_valid
    expect(postal).not_to be_valid
  end

  it 'only physically deletes a draft without operational history' do
    incident = incident_with_scope
    incident.save!
    TechnicalIncidents::AuditService.record!(
      incident: incident,
      action: 'incident.created',
      origin: 'ui'
    )

    expect(incident).to be_deletable_draft
    expect do
      incident.transaction do
        incident.updates.delete_all(:delete_all)
        incident.destroy!
      end
    end.to change(described_class, :count).by(-1)

    incident = incident_with_scope
    incident.save!
    create(
      :technical_incident_evaluation,
      account: account,
      conversation: create(:conversation, account: account),
      technical_incident: incident
    )
    expect(incident.reload).not_to be_deletable_draft
  end
end
