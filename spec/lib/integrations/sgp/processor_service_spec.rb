require 'rails_helper'

RSpec.describe Integrations::Sgp::ProcessorService do
  subject(:service) { described_class.new(account: account, conversation: conversation, user: agent) }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { conversation.contact }
  let(:client) { instance_double(Integrations::Sgp::Client) }

  before do
    allow(Integrations::Sgp::Client).to receive(:new).and_return(client)
  end

  it 'persists the document and allowlisted SGP fields' do
    allow(client).to receive(:perform).and_return(
      ok: true,
      cpf_cnpj: '52998224725',
      nome: 'Cliente Teste',
      contrato: '123',
      contrato_id: '456',
      onu: 'ONU-1',
      status_onu: 'ONLINE',
      plano: '600 Mega',
      status_contrato: 'ATIVO',
      fatura_status: 'ABERTA',
      fatura_vencimento: '2026-06-10',
      fatura_valor: '99.90',
      pix_disponivel: true,
      faturas: [
        {
          id: '405488',
          numero: '309442',
          vencimento: '2026-06-15',
          valor: '60.00',
          pix_disponivel: true
        }
      ],
      ignored_secret: 'must-not-be-persisted'
    )

    result = service.perform(action: 'consultar_sgp_por_cpf', cpf_cnpj: '529.982.247-25')

    expect(result[:ok]).to be(true)
    expect(contact.reload.custom_attributes).to include(
      'sgp_cpf_cnpj' => '52998224725',
      'sgp_nome_titular' => 'Cliente Teste',
      'sgp_status_onu' => 'ONLINE',
      'sgp_faturas' => [
        {
          'id' => '405488',
          'numero' => '309442',
          'vencimento' => '2026-06-15',
          'valor' => '60.00',
          'pix_disponivel' => true
        }
      ]
    )
    expect(contact.custom_attributes).not_to have_key('ignored_secret')
  end

  it 'keeps the valid document when n8n is unavailable' do
    allow(client).to receive(:perform).and_raise(Integrations::Sgp::Client::Error, 'timeout')

    result = service.perform(action: 'consultar_sgp_por_cpf', cpf_cnpj: '52998224725')

    expect(result).to include(ok: false, reason: 'sgp_indisponivel', cpf_saved: true)
    expect(contact.reload.custom_attributes['sgp_cpf_cnpj']).to eq('52998224725')
  end

  it 'uses the stored custom attribute for an ONU status query' do
    contact.update!(custom_attributes: {
                      'sgp_cpf_cnpj' => '52998224725',
                      'sgp_contrato_id' => '456',
                      'sgp_onu' => 'ONU-1'
                    })
    allow(client).to receive(:perform).and_return(ok: true, status_onu: 'ONLINE')

    service.perform(action: 'consultar_status_onu')

    expect(client).to have_received(:perform).with(
      hash_including(
        action: 'consultar_status_onu',
        cpf_cnpj: '52998224725',
        contract_id: '456',
        onu: 'ONU-1'
      )
    )
  end

  it 'sends only the delivery content returned by n8n' do
    contact.update!(custom_attributes: {
                      'sgp_cpf_cnpj' => '52998224725',
                      'sgp_contrato_id' => '456'
                    })
    allow(client).to receive(:perform).and_return(
      ok: true,
      message: 'Pix enviado.',
      delivery_content: 'https://example.test/pix/405488/html/'
    )
    message = instance_double(Message, id: 321)
    builder = instance_double(Messages::MessageBuilder, perform: message)
    allow(Messages::MessageBuilder).to receive(:new).and_return(builder)

    result = service.perform(action: 'enviar_pix', fatura_id: '405488')

    expect(client).to have_received(:perform).with(hash_including(action: 'enviar_pix', fatura_id: '405488'))
    expect(Messages::MessageBuilder).to have_received(:new).with(
      agent,
      conversation,
      {
        content: 'https://example.test/pix/405488/html/',
        message_type: 'outgoing',
        private: false,
        content_type: 'text'
      }
    )
    expect(result).to include(ok: true, message_id: 321)
    expect(result).not_to have_key(:delivery_content)
  end

  it 'does not send a customer message for payment promise feedback' do
    contact.update!(custom_attributes: { 'sgp_cpf_cnpj' => '52998224725', 'sgp_contrato_id' => '456' })
    allow(client).to receive(:perform).and_return(ok: true, message: 'Promessa liberada por 2 dias.')
    allow(Messages::MessageBuilder).to receive(:new)

    result = service.perform(action: 'liberar_promessa_2_dias')

    expect(result).to include(ok: true, message: 'Promessa liberada por 2 dias.')
    expect(Messages::MessageBuilder).not_to have_received(:new)
  end

  it 'rejects invalid documents without calling n8n' do
    result = service.perform(action: 'consultar_sgp_por_cpf', cpf_cnpj: '111.111.111-11')

    expect(result).to include(ok: false, reason: 'cpf_invalido')
    expect(client).not_to have_received(:perform)
  end
end
