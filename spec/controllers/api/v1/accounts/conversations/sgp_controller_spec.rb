require 'rails_helper'

RSpec.describe 'Conversation SGP API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:processor) { instance_double(Integrations::Sgp::ProcessorService) }
  let(:endpoint) do
    api_v1_account_conversation_sgp_url(
      account_id: account.id,
      conversation_id: conversation.display_id
    )
  end

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    allow(Integrations::Sgp::ProcessorService).to receive(:new).and_return(processor)
  end

  it 'requires authentication' do
    post endpoint, params: { action: 'consultar_sgp_por_cpf', cpf_cnpj: '52998224725' }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the processor response to an authorized agent' do
    allow(processor).to receive(:perform).and_return(ok: true, contact_id: conversation.contact_id)

    post endpoint,
         params: { action: 'consultar_sgp_por_cpf', cpf_cnpj: '52998224725' },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('ok' => true, 'contact_id' => conversation.contact_id)
  end

  it 'maps SGP availability failures to service unavailable' do
    allow(processor).to receive(:perform).and_return(
      ok: false,
      reason: 'sgp_indisponivel',
      message: 'O SGP está indisponível no momento.'
    )

    post endpoint,
         params: { action: 'consultar_status_onu' },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:service_unavailable)
  end
end
