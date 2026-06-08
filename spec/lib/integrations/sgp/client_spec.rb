require 'rails_helper'

RSpec.describe Integrations::Sgp::Client do
  subject(:client) { described_class.new }

  let(:url) { 'https://n8n.example.com/webhook/chatwoot-sgp' }
  let(:secret) { 'server-only-secret' }
  let(:payload) { { action: 'consultar_sgp_por_cpf', cpf_cnpj: '52998224725' } }

  it 'posts JSON to n8n with the server-side secret header' do
    stub_request(:post, url)
      .with(
        headers: { 'X-Chatwoot-SGP-Secret' => secret },
        body: payload.to_json
      )
      .to_return(status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })

    with_modified_env(
      'N8N_CHATWOOT_WEBHOOK_URL' => url,
      'N8N_CHATWOOT_WEBHOOK_SECRET' => secret,
      'N8N_CHATWOOT_TIMEOUT_SECONDS' => '15'
    ) do
      expect(client.perform(payload)).to eq(ok: true)
    end
  end

  it 'fails without exposing configuration values when n8n is not configured' do
    with_modified_env(
      'N8N_CHATWOOT_WEBHOOK_URL' => nil,
      'N8N_CHATWOOT_WEBHOOK_SECRET' => nil
    ) do
      expect { client.perform(payload) }.to raise_error(described_class::ConfigurationError)
    end
  end

  it 'rejects non-success responses' do
    stub_request(:post, url).to_return(status: 503, body: '{}')

    with_modified_env(
      'N8N_CHATWOOT_WEBHOOK_URL' => url,
      'N8N_CHATWOOT_WEBHOOK_SECRET' => secret
    ) do
      expect { client.perform(payload) }.to raise_error(described_class::Error, /HTTP 503/)
    end
  end

  it 'returns structured business errors from n8n' do
    stub_request(:post, url).to_return(
      status: 422,
      body: { ok: false, reason: 'cpf_nao_encontrado' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    with_modified_env(
      'N8N_CHATWOOT_WEBHOOK_URL' => url,
      'N8N_CHATWOOT_WEBHOOK_SECRET' => secret
    ) do
      expect(client.perform(payload)).to include(
        ok: false,
        reason: 'cpf_nao_encontrado'
      )
    end
  end
end
