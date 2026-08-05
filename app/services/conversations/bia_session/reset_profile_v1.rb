class Conversations::BiaSession::ResetProfileV1
  PROFILE = 'bia_session_v1'.freeze
  DOMAIN_STATE_KEYS = %w[financeiro_state suporte_state cadastro_state transferencia_state].freeze
  TRANSIENT_TOP_LEVEL_KEYS = %w[
    pending_question pending_confirmation bia_pending_question bia_pending_confirmation
    bia_intent bia_clarification_attempts bia_media_context transferencia_pendente
    handoff_pendente promessa_pagamento_pendente liberacao_ativa
  ].freeze
  TRANSIENT_DOMAIN_KEYS = %w[
    step etapa pending_question pending_confirmation confirmation intent clarification_attempts
    attempts media_pending handoff_pending operation_pending release_pending selection_expires_at
  ].freeze

  def apply(attributes:, generation:, source_message_id:, timestamp:)
    result = attributes.deep_dup
    TRANSIENT_TOP_LEVEL_KEYS.each { |key| result.delete(key) }
    DOMAIN_STATE_KEYS.each { |key| result[key] = reset_domain_state(result[key]) if result[key].is_a?(Hash) }
    result.merge(
      'bia_context_reset_required' => false,
      'bia_context_reset_generation' => generation,
      'bia_context_reset_message_id' => source_message_id,
      'bia_context_reset_at' => timestamp.iso8601
    )
  end

  private

  def reset_domain_state(value)
    value.deep_dup.except(*TRANSIENT_DOMAIN_KEYS)
  end
end
