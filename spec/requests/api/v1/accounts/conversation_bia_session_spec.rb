require 'rails_helper'

RSpec.describe 'Conversation Bia session API', type: :request do
  let(:account) { create(:account).tap { |record| record.enable_features!('conversation_return_to_bia') } }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:headers) { { api_access_token: agent_bot.access_token.token } }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :open,
      label_list: ['bot-bia'],
      custom_attributes: {
        'bia_automation_state' => 'active',
        'bia_session_generation' => 5,
        'bia_resume_after_message_id' => 0,
        'bia_context_reset_required' => true,
        'bia_retorno_humano_pendente' => false,
        'pending_question' => 'must-not-survive',
        'unrelated' => 'preserved'
      }
    )
  end
  let!(:source_message) do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming, private: false)
  end
  let(:base_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/bia_session" }

  it 'resets context through an authenticated account-scoped AgentBot token' do
    post "#{base_path}/reset_context",
         headers: headers,
         params: {
           expected_generation: 5,
           source_message_id: source_message.id,
           idempotency_key: "bia-reset-#{SecureRandom.uuid}",
           reset_profile: 'bia_session_v1'
         },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'accepted', 'reason_code' => 'context_reset_applied')
    expect(response.parsed_body.dig('session', 'generation')).to eq(5)
    expect(conversation.reload.custom_attributes).to include(
      'bia_context_reset_required' => false,
      'unrelated' => 'preserved'
    )
    expect(conversation.custom_attributes).not_to have_key('pending_question')
  end

  it 'returns an authoritative 409 and does not restore stale attributes' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_session_generation' => 6, 'new_attribute' => true))

    post "#{base_path}/reset_context",
         headers: headers,
         params: {
           expected_generation: 5,
           source_message_id: source_message.id,
           idempotency_key: "bia-reset-#{SecureRandom.uuid}",
           reset_profile: 'bia_session_v1'
         },
         as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('reason_code' => 'stale_session_generation')
    expect(response.parsed_body.dig('session', 'generation')).to eq(6)
    expect(conversation.reload.custom_attributes).to include('bia_session_generation' => 6, 'new_attribute' => true)
  end

  it 'creates a public response only after reset and never duplicates a replay' do
    conversation.update!(custom_attributes: conversation.custom_attributes.merge('bia_context_reset_required' => false))
    idempotency_key = "bia-send-#{SecureRandom.uuid}"
    payload = {
      expected_generation: 5,
      source_message_id: source_message.id,
      idempotency_key: idempotency_key,
      content: 'Resposta de contrato',
      content_type: 'text',
      private: false
    }

    2.times { post "#{base_path}/messages", headers: headers, params: payload, as: :json }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'duplicate', 'reason_code' => 'idempotency_replay')
    expect(conversation.messages.where(content: 'Resposta de contrato', private: false).count).to eq(1)
  end

  it 'does not expose the operations while the return feature is disabled' do
    account.disable_features!('conversation_return_to_bia')

    post "#{base_path}/reset_context",
         headers: headers,
         params: {
           expected_generation: 5,
           source_message_id: source_message.id,
           idempotency_key: "bia-reset-#{SecureRandom.uuid}",
           reset_profile: 'bia_session_v1'
         },
         as: :json

    expect(response).to have_http_status(:not_found)
  end
end
