class Integrations::Sgp::ProcessorService
  pattr_initialize [:account!, :conversation!, :user!]

  ACTIONS = %w[
    consultar_sgp_por_cpf
    consultar_status_onu
    enviar_pix
    enviar_barras
    enviar_pdf
    enviar_link_pagamento
    liberar_promessa_2_dias
  ].freeze
  DELIVERY_ACTIONS = %w[enviar_pix enviar_barras enviar_pdf enviar_link_pagamento].freeze
  RESPONSE_ATTRIBUTES = {
    cpf_cnpj: 'sgp_cpf_cnpj',
    nome: 'sgp_nome_titular',
    contrato: 'sgp_contrato',
    contrato_id: 'sgp_contrato_id',
    onu: 'sgp_onu',
    status_onu: 'sgp_status_onu',
    plano: 'sgp_plano',
    status_contrato: 'sgp_status_contrato',
    fatura_status: 'sgp_fatura_status',
    fatura_vencimento: 'sgp_fatura_vencimento',
    fatura_valor: 'sgp_fatura_valor',
    pix_disponivel: 'sgp_pix_disponivel',
    codigo_barras_disponivel: 'sgp_codigo_barras_disponivel',
    pdf_disponivel: 'sgp_pdf_disponivel',
    link_cobranca_disponivel: 'sgp_link_cobranca_disponivel',
    faturas: 'sgp_faturas',
    updated_at: 'sgp_atualizado_em'
  }.freeze

  def perform(action:, cpf_cnpj: nil, fatura_id: nil)
    return error('acao_invalida', 'Ação SGP inválida.') unless ACTIONS.include?(action)

    document = document_for(action, cpf_cnpj)
    return error('cpf_invalido', 'Informe um CPF ou CNPJ válido.') unless document_validator.valid?(document)

    persist_document(document)
    request_id = SecureRandom.uuid
    log_request(request_id, action, 'started')
    response = client.perform(payload(action, document, request_id, fatura_id))

    return handle_error_response(response, request_id, action) unless response[:ok]

    persist_response(response)
    message = create_delivery_message(response[:delivery_content]) if DELIVERY_ACTIONS.include?(action)
    log_request(request_id, action, 'completed')
    response.slice(:ok, :reason, :message, :request_id).merge(
      cpf_saved: true,
      contact_id: contact.id,
      message_id: message&.id,
      custom_attributes: contact.custom_attributes.slice(*RESPONSE_ATTRIBUTES.values)
    ).compact
  rescue Integrations::Sgp::Client::ConfigurationError => e
    log_failure(request_id, action, e)
    error('configuracao_incompleta', 'Integração SGP não configurada.', cpf_saved: document.present?, request_id: request_id)
  rescue Integrations::Sgp::Client::Error => e
    log_failure(request_id, action, e)
    error('sgp_indisponivel', 'O SGP está indisponível no momento.', cpf_saved: document.present?, request_id: request_id)
  rescue StandardError => e
    log_failure(request_id, action, e)
    error('resposta_sgp_invalida', 'Não foi possível processar a resposta do SGP.', cpf_saved: document.present?, request_id: request_id)
  end

  private

  def contact
    @contact ||= conversation.contact
  end

  def client
    @client ||= Integrations::Sgp::Client.new
  end

  def document_validator
    Integrations::Sgp::DocumentValidator
  end

  def document_for(action, value)
    return document_validator.normalize(value) if action == 'consultar_sgp_por_cpf'

    contact.custom_attributes['sgp_cpf_cnpj'] || contact.additional_attributes['cpf']
  end

  def persist_document(document)
    contact.update!(custom_attributes: contact.custom_attributes.merge('sgp_cpf_cnpj' => document))
  end

  def persist_response(response)
    attributes = RESPONSE_ATTRIBUTES.each_with_object({}) do |(response_key, attribute_key), memo|
      memo[attribute_key] = response[response_key] if response.key?(response_key)
    end
    attributes['sgp_atualizado_em'] ||= Time.current.iso8601

    contact.update!(custom_attributes: contact.custom_attributes.merge(attributes))
  end

  def payload(action, document, request_id, fatura_id)
    {
      action: action,
      account_id: account.id,
      conversation_id: conversation.display_id,
      contact_id: contact.id,
      cpf_cnpj: document,
      contract_id: contact.custom_attributes['sgp_contrato_id'],
      fatura_id: fatura_id.presence,
      onu: contact.custom_attributes['sgp_onu'],
      source: 'chatwoot_sidebar',
      request_id: request_id
    }
  end

  def create_delivery_message(content)
    raise Integrations::Sgp::Client::Error, 'n8n returned empty delivery content' if content.blank?

    Messages::MessageBuilder.new(
      user,
      conversation,
      { content: content.to_s, message_type: 'outgoing', private: false, content_type: 'text' }
    ).perform
  end

  def handle_error_response(response, request_id, action)
    reason = response[:reason].presence || 'resposta_sgp_invalida'
    message = response[:message].presence || 'Não foi possível consultar o SGP.'
    log_request(request_id, action, reason)
    error(reason, message, cpf_saved: true, request_id: response[:request_id] || request_id)
  end

  def error(reason, message, extra = {})
    { ok: false, reason: reason, message: message }.merge(extra)
  end

  def log_request(request_id, action, status)
    Rails.logger.info(
      "[SGP] request_id=#{request_id} account_id=#{account.id} conversation_id=#{conversation.display_id} " \
      "contact_id=#{contact.id} action=#{action} status=#{status}"
    )
  end

  def log_failure(request_id, action, error)
    Rails.logger.error(
      "[SGP] request_id=#{request_id} account_id=#{account.id} conversation_id=#{conversation.display_id} " \
      "contact_id=#{contact.id} action=#{action} error=#{error.class}"
    )
  end
end
