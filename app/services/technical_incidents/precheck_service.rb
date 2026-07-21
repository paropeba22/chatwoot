class TechnicalIncidents::PrecheckService
  CONTRACT_VERSION = '1.0'.freeze

  def initialize(account:, agent_bot:, payload:)
    @account = account
    @agent_bot = agent_bot
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @effective_mode = TechnicalIncidents::Configuration.effective_mode(@payload['mode'])
    return unavailable_response if @effective_mode == 'disabled'

    perform_precheck
  rescue ActiveRecord::RecordNotFound
    { contract_version: CONTRACT_VERSION, status: 'stale', reason_code: 'conversation_not_found' }
  rescue ActiveRecord::RecordNotUnique
    response(existing_evaluation, duplicate: true)
  rescue ArgumentError => e
    TechnicalIncidents::Instrumentation.record(event: 'precheck', status: 'fallback', reason_code: e.message)
    { contract_version: CONTRACT_VERSION, status: 'fallback', reason_code: e.message }
  end

  private

  def perform_precheck
    classification = sanitized_classification
    validate_payload!(classification)
    gate = TechnicalIncidents::SemanticGate.call(classification)
    record_semantic_gate(gate)
    existing = existing_evaluation
    return response(existing, duplicate: true) if existing

    conversation = @account.conversations.find_by!(display_id: @payload['conversation_display_id'])
    outcome = TechnicalIncidents::PrecheckDecision.new(
      account: @account, classification: classification, semantic_gate: gate
    ).call
    record_candidate_ranking(outcome)
    evaluation = create_evaluation(conversation, classification, outcome)
    audit_evaluation(conversation, outcome)
    record_precheck(conversation, evaluation, outcome)
    response(evaluation)
  end

  def sanitized_classification
    raw = @payload['classification'] || @payload['semantic_classification']
    TechnicalIncidents::SemanticFilter.sanitize(raw)
  end

  def existing_evaluation
    existing = @account.technical_incident_evaluations.find_by(request_id: request_id)
    return existing if existing || @payload['source_message_id'].blank?

    @account.technical_incident_evaluations.find_by(source_message_id: @payload['source_message_id'])
  end

  def request_id
    @payload['request_id'].presence || @payload['idempotency_key'].presence || raise(ArgumentError, 'request_id_required')
  end

  def validate_payload!(classification)
    raise ArgumentError, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
    raise ArgumentError, 'automation_actor_invalid' unless valid_automation_actor?
    raise ArgumentError, 'contract_version_unsupported' unless @payload['contract_version'].to_s == CONTRACT_VERSION
    raise ArgumentError, 'invalid_mode' unless TechnicalIncidentEvaluation::MODES.include?(@payload['mode'])
    raise ArgumentError, 'invalid_classification' unless classification.is_a?(Hash)
  end

  def valid_automation_actor?
    @agent_bot && @agent_bot.bot_config.to_h['technical_incidents_api'] == true
  end

  def create_evaluation(conversation, classification, outcome)
    @account.technical_incident_evaluations.create!(
      conversation: conversation,
      agent_bot: @agent_bot,
      technical_incident: outcome[:incident],
      request_id: request_id,
      source_message_id: @payload['source_message_id'],
      contract_version: CONTRACT_VERSION,
      mode: @effective_mode,
      status: outcome[:status],
      reason_code: outcome[:reason_code],
      classification: classification,
      candidate_snapshot: outcome[:candidates].map(&:customer_visible_snapshot),
      operational_confidence: classification['semantic_confidence'],
      latency_ms: elapsed_ms,
      expires_at: 20.minutes.from_now
    )
  end

  def audit_evaluation(conversation, outcome)
    return unless outcome[:incident]

    TechnicalIncidents::AuditService.record!(
      incident: outcome[:incident],
      action: 'evaluation.precheck',
      actor: @agent_bot,
      origin: 'automation',
      request_id: request_id,
      changeset: evaluation_changeset(conversation, outcome)
    )
  end

  def evaluation_changeset(conversation, outcome)
    { conversation_id: conversation.id, decision: outcome[:status], reason_code: outcome[:reason_code] }
  end

  def record_semantic_gate(gate)
    TechnicalIncidents::Instrumentation.record(
      event: 'semantic_gate',
      request_id: request_id,
      status: gate.allowed ? gate.confidence_level : gate.status,
      reason_code: gate.reason_code
    )
  end

  def record_candidate_ranking(outcome)
    TechnicalIncidents::Instrumentation.record(
      event: 'candidate_ranking',
      request_id: request_id,
      incident_id: outcome[:incident]&.id,
      status: outcome[:status],
      reason_code: outcome[:reason_code]
    )
  end

  def record_precheck(conversation, evaluation, outcome)
    TechnicalIncidents::Instrumentation.record(
      event: 'precheck',
      request_id: request_id,
      evaluation_id: evaluation.opaque_id,
      incident_id: outcome[:incident]&.id,
      conversation_id: conversation.id,
      status: outcome[:status],
      reason_code: outcome[:reason_code],
      duration_ms: evaluation.latency_ms
    )
  end

  def unavailable_response
    { contract_version: CONTRACT_VERSION, status: 'fallback', reason_code: 'server_automation_disabled' }
  end

  def response(evaluation, duplicate: false)
    return unavailable_response unless evaluation

    incident = evaluation.technical_incident
    {
      contract_version: CONTRACT_VERSION,
      id: evaluation.opaque_id,
      check_id: evaluation.opaque_id,
      evaluation_id: evaluation.opaque_id,
      commit_token: evaluation.opaque_id,
      status: duplicate ? 'duplicate' : evaluation.status,
      reason_code: duplicate ? 'duplicate_request' : evaluation.reason_code,
      incident: incident&.customer_visible_snapshot,
      customer_message: incident && TechnicalIncidents::TemplateRenderer.render(incident),
      notification_version: incident&.notification_version,
      expires_at: evaluation.expires_at
    }.compact
  end

  def elapsed_ms
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1_000).round
  end
end
