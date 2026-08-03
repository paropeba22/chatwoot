require 'rails_helper'

RSpec.describe 'Conversation automation transitions API', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_send_to_human_queue') } }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, label_list: ['bot-bia', 'retained']) }
  let(:message) { create(:message, account: account, conversation: conversation, inbox: conversation.inbox) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/automation_transitions" }
  let(:params) do
    {
      action: 'send_to_human_queue',
      idempotency_key: "queue-#{SecureRandom.uuid}",
      expected_last_message_id: message.id
    }
  end

  before { create(:inbox_member, user: agent, inbox: conversation.inbox) }

  it 'returns the authoritative conversation after a successful transition' do
    post path, headers: agent.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('status' => 'accepted', 'reason_code' => 'sent_to_human_queue')
    expect(body['transition_id']).to be_present
    expect(body.dig('conversation', 'status')).to eq('open')
    expect(body.dig('conversation', 'meta', 'assignee')).to be_nil
    expect(body.dig('conversation', 'labels')).to contain_exactly('aguardando-humano', 'retained')
    expect(body.dig('conversation', 'custom_attributes', 'bia_retorno_humano_pendente')).to be(true)
  end

  it 'returns duplicate without creating another note for a retry' do
    post path, headers: agent.create_new_auth_token, params: params, as: :json
    post path, headers: agent.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('duplicate')
    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.automation_transitions.count).to eq(1)
  end

  it 'returns conflict with the authoritative conversation for a stale message' do
    stale_params = params.merge(expected_last_message_id: message.id - 1)

    post path, headers: agent.create_new_auth_token, params: stale_params, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('status' => 'conflict', 'reason_code' => 'stale_last_message')
    expect(response.parsed_body['conversation']).to be_present
    expect(conversation.reload.label_list).to include('bot-bia')
  end

  it 'does not expose or accept the endpoint while the feature is disabled' do
    account.disable_features!('conversation_send_to_human_queue')

    post path, headers: agent.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('feature_disabled')
  end

  it 'forbids an agent without access to the inbox' do
    other_agent = create(:user, account: account, role: :agent)

    post path, headers: other_agent.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'does not find a conversation through another account' do
    other_account = create(:account).tap { |record| record.enable_features!('conversation_send_to_human_queue') }
    other_agent = create(:user, account: other_account, role: :administrator)
    cross_account_path = "/api/v1/accounts/#{other_account.id}/conversations/#{conversation.display_id}/automation_transitions"

    post cross_account_path, headers: other_agent.create_new_auth_token, params: params, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
