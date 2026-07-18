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
