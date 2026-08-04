require 'rails_helper'

RSpec.describe 'Technical incident account API', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('technical_incidents') } }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { { api_access_token: administrator.access_token.token } }
  let(:incident_params) do
    {
      title: 'Instabilidade controlada',
      incident_type: 'unplanned_outage',
      severity: 'major',
      priority: 70,
      problem_types: ['internet_connectivity'],
      affected_services: ['internet'],
      customer_message: 'Identificamos uma instabilidade.',
      action: 'message_and_handoff',
      scope_groups_attributes: [
        {
          position: 0,
          criteria_attributes: [{ criterion_type: 'general', operator: 'in', values: [] }]
        }
      ]
    }
  end

  it 'creates and lists an account-scoped draft with nested allowlisted scopes' do
    post "/api/v1/accounts/#{account.id}/technical_incidents",
         params: { technical_incident: incident_params },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    incident_id = response.parsed_body.fetch('id')

    get "/api/v1/accounts/#{account.id}/technical_incidents", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 0, 'id')).to eq(incident_id)
    expect(account.technical_incidents.find(incident_id).scope_groups.first.criteria.first).to be_general
  end

  it 'returns ordered, structured metadata from the canonical backend taxonomies' do
    get "/api/v1/accounts/#{account.id}/technical_incidents/options", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    metadata = response.parsed_body
    expect(metadata.fetch('metadata_version')).to eq(1)
    expect(metadata.fetch('incident_types').first).to include(
      'value' => 'unplanned_outage',
      'label' => 'Unplanned outage',
      'label_key' => 'TECHNICAL_INCIDENTS.CATALOG.INCIDENT_TYPES.UNPLANNED_OUTAGE'
    )
    expect(metadata.fetch('severities').pluck('value')).to eq(TechnicalIncident::SEVERITIES)
    expect(metadata.fetch('affected_services').pluck('value')).to eq(TechnicalIncident::SERVICE_KEYS)
    expect(metadata.fetch('scope_fields').find { |field| field['value'] == 'city_neighborhood' }).to include(
      'allowed_operators' => ['in'],
      'value_type' => 'location_pairs',
      'value_fields' => %w[city neighborhood]
    )
  end

  it 'rejects incomplete scope groups without creating an incident, conversation, or message' do
    invalid_params = incident_params.deep_dup
    invalid_params[:scope_groups_attributes] = [{ position: 0, criteria_attributes: [] }]

    expect do
      post "/api/v1/accounts/#{account.id}/technical_incidents",
           params: { technical_incident: invalid_params },
           headers: headers,
           as: :json
    end.not_to change { [TechnicalIncident.count, Conversation.count, Message.count] }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects incompatible operators and empty affected service catalogs' do
    invalid_params = incident_params.deep_dup
    invalid_params[:affected_services] = []
    invalid_params[:scope_groups_attributes][0][:criteria_attributes][0][:operator] = 'equals'

    post "/api/v1/accounts/#{account.id}/technical_incidents",
         params: { technical_incident: invalid_params },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(TechnicalIncident.where(account: account, title: invalid_params[:title])).not_to exist
  end

  it 'persists AND criteria within a group and OR between multiple groups' do
    grouped_params = incident_params.deep_dup
    grouped_params[:scope_groups_attributes] = [
      {
        position: 0,
        criteria_attributes: [
          { criterion_type: 'city_neighborhood', operator: 'in', values: [{ city: 'Recife', neighborhood: 'Centro' }] },
          { criterion_type: 'service_specific', operator: 'in', values: ['internet'] }
        ]
      },
      {
        position: 1,
        criteria_attributes: [{ criterion_type: 'pop_id', operator: 'in', values: ['5'] }]
      }
    ]

    post "/api/v1/accounts/#{account.id}/technical_incidents",
         params: { technical_incident: grouped_params },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('scope_groups').size).to eq(2)
    expect(response.parsed_body.dig('scope_groups', 0, 'criteria').size).to eq(2)
  end

  it 'hides the API and performs no write while the feature is disabled' do
    account.disable_features!('technical_incidents')

    expect do
      post "/api/v1/accounts/#{account.id}/technical_incidents",
           params: { technical_incident: incident_params },
           headers: headers,
           as: :json
    end.not_to change(TechnicalIncident, :count)

    expect(response).to have_http_status(:not_found)
  end

  it 'returns HTTP 409 for a stale optimistic lock version' do
    incident = create(:technical_incident, account: account)
    stale_version = incident.lock_version
    incident.update!(title: 'Updated elsewhere')

    patch "/api/v1/accounts/#{account.id}/technical_incidents/#{incident.id}",
          params: {
            technical_incident: {
              title: 'Conflicting update',
              lock_version: stale_version
            }
          },
          headers: headers,
          as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('record_conflict')
  end

  it 'does not allow account spoofing through the URL' do
    other_account = create(:account).tap { |record| record.enable_features!('technical_incidents') }

    get "/api/v1/accounts/#{other_account.id}/technical_incidents", headers: headers, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
