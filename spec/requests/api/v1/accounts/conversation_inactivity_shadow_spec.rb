require 'rails_helper'

RSpec.describe 'Conversation inactivity shadow report', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_inactivity_shadow') } }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { { api_access_token: administrator.access_token.token } }

  before do
    conversation = create(:conversation, account: account)
    ConversationInactivityShadowAssessment.create!(
      account: account,
      conversation: conversation,
      classification: 'waiting_customer',
      reason_code: 'latest_public_message_outgoing',
      operational_bucket: 'bia',
      session_generation: 4,
      customer_wait_seconds: 600,
      confidence: 0.9,
      observed_at: Time.current
    )
  end

  it 'returns only aggregate, non-sensitive shadow results to administrators' do
    get "/api/v1/accounts/#{account.id}/conversation_inactivity_shadow", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('total')).to eq(1)
    expect(response.parsed_body.dig('groups', 0)).to include(
      'classification' => 'waiting_customer',
      'count' => 1,
      'operational_bucket' => 'bia'
    )
    expect(response.body).not_to include('conversation_id', 'content', 'phone_number')
  end

  it 'hides the report while the feature is disabled' do
    account.disable_features!('conversation_inactivity_shadow')

    get "/api/v1/accounts/#{account.id}/conversation_inactivity_shadow", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects non-administrators' do
    agent = create(:user, account: account, role: :agent)

    get "/api/v1/accounts/#{account.id}/conversation_inactivity_shadow",
        headers: { api_access_token: agent.access_token.token }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
