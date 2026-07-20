class TechnicalIncidents::PrecheckService
  CONTRACT_VERSION = '1.0'.freeze

  def initialize(account:, agent_bot:, payload:)
    @account = account
    @agent_bot = agent_bot
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @effective_mode = TechnicalIncidents::Configuration.effective_mode(@payload['mode'])
    return unavailable_response if @effective_mode == 'disabled'

    classification = TechnicalIncidents::SemanticFilter.sanitize(@payload['classification'] || @payload['semantic_classification'])
    validate_payload!(classification)
    semantic_gate = TechnicalIncidents::SemanticGate.call(classification)
    TechnicalIncidents::Instrumentation.record(
      event: 'semantic_gate',
      request_id: request_id,
      status: semantic_gate.allowed ? semantic_gate.confidence_level : semantic_gate.status,
      reason_code: semantic_gate.reason_code
    )

    existing = @account.technical_incident_evaluations.find_by(request_id: request_id)
    if @payload['source_message_id'].present?
      existing ||= @account.technical_incident_evaluations.find_by(source_message_id: @payload['source_message_id'])
    end
    return response(existing, duplicate: true) if existing

    conversation = @account.conversations.find_by!(display_id: @payload['conversation_display_id'])
    candidates = semantic_gate.allowed ? compatible_candidates(classification, semantic_gate) : []
    decision = if semantic_gate.allowed
                 candidates.empty? ? inactive_decision(classification) : decide(candidates)
               else
                 { status: semantic_gate.status, reason_code: semantic_gate.reason_code }
               end
    TechnicalIncidents::Instrumentation.record(
      event: 'candidate_ranking',
      request_id: request_id,
      incident_id: decision[:incident]&.id,
      status: decision[:status],
      reason_code: decision[:reason_code]
    )
    evaluation = @account.technical_incident_evaluations.create!(
      conversation: conversation,
      agent_bot: @agent_bot,
      technical_incident: decision[:incident],
      request_id: request_id,
      source_message_id: @payload['source_message_id'],
      contract_version: CONTRACT_VERSION,
      mode: @effective_mode,
      status: decision[:status],
      reason_code: decision[:reason_code],
      classification: classification,
      candidate_snapshot: candidates.map(&:customer_visible_snapshot),
      operational_confidence: classification['semantic_confidence'],
      latency_ms: elapsed_ms(started_at),
      expires_at: 20.minutes.from_now
    )

    TechnicalIncidents::AuditService.record!(
      incident: decision[:incident],
      action: 'evaluation.precheck',
      actor: @agent_bot,
      origin: 'automation',
      request_id: request_id,
      changeset: { conversation_id: conversation.id, decision: decision[:status], reason_code: decision[:reason_code] }
    ) if decision[:incident]
    TechnicalIncidents::Instrumentation.record(
      event: 'precheck',
      request_id: request_id,
      evaluation_id: evaluation.opaque_id,
      incident_id: decision[:incident]&.id,
      conversation_id: conversation.id,
      status: decision[:status],
      reason_code: decision[:reason_code],
      duration_ms: evaluation.latency_ms
    )
    response(evaluation)
  rescue ActiveRecord::RecordNotFound
    { contract_version: CONTRACT_VERSION, status: 'stale', reason_code: 'conversation_not_found' }
  rescue ActiveRecord::RecordNotUnique
    duplicate = @account.technical_incident_evaluations.find_by(request_id: request_id)
    duplicate ||= @account.technical_incident_evaluations.find_by(source_message_id: @payload['source_message_id'])
    response(duplicate, duplicate: true)
  rescue ArgumentError => e
    TechnicalIncidents::Instrumentation.record(event: 'precheck', status: 'fallback', reason_code: e.message)
    { contract_version: CONTRACT_VERSION, status: 'fallback', reason_code: e.message }
  end

  private

  def request_id
    @payload['request_id'].presence || @payload['idempotency_key'].presence || raise(ArgumentError, 'request_id_required')
  end

  def validate_payload!(classification)
    raise ArgumentError, 'feature_disabled' unless @account.feature_enabled?('technical_incidents')
    unless @agent_bot && @agent_bot.bot_config.to_h['technical_incidents_api'] == true
      raise ArgumentError, 'automation_actor_invalid'
    end
    raise ArgumentError, 'contract_version_unsupported' unless @payload['contract_version'].to_s == CONTRACT_VERSION
    raise ArgumentError, 'invalid_mode' unless TechnicalIncidentEvaluation::MODES.include?(@payload['mode'])
    raise ArgumentError, 'invalid_classification' unless classification.is_a?(Hash)
  end

  def decide(candidates)
    general = candidates.select(&:general_scope?).map { |incident| { incident: incident, specificity: 0 } }
    localized = candidates.reject(&:general_scope?)
    ranked_general = TechnicalIncidents::CandidateRanker.sort(general)

    # A localized candidate must be resolved against the selected contract before
    # a broader incident can win. MatchService ranks all candidates afterwards.
    if localized.any?
      return { status: 'localized_candidate', reason_code: 'localized_candidates_available', incident: localized.first }
    end

    if ranked_general.any?
      return { status: 'ambiguous', reason_code: 'general_candidate_tie' } if TechnicalIncidents::CandidateRanker.ambiguous?(ranked_general)

      return { status: 'general_match', reason_code: 'semantic_general_match', incident: ranked_general.first[:incident] }
    end

    { status: 'no_candidate', reason_code: 'no_semantic_candidate' }
  end

  def inactive_decision(classification)
    compatible = semantic_scope(@account.technical_incidents.not_archived.where(status: %w[active monitoring expired]), classification)
                 .includes(scope_groups: :criteria)
                 .select { |incident| TechnicalIncidents::SemanticFilter.compatible?(incident, classification) }
    return { status: 'fallback', reason_code: 'incident_monitoring' } if compatible.any? { |incident| incident.status == 'monitoring' }
    if compatible.any? { |incident| incident.status == 'expired' || (incident.expires_at.present? && incident.expires_at <= Time.current) }
      return { status: 'expired', reason_code: 'incident_expired' }
    end

    { status: 'no_candidate', reason_code: 'no_semantic_candidate' }
  end

  def compatible_candidates(classification, semantic_gate)
    candidates = semantic_scope(@account.technical_incidents.intercepting, classification)
                 .includes(scope_groups: :criteria)
                 .select { |incident| TechnicalIncidents::SemanticFilter.compatible?(incident, classification) }
    return candidates if semantic_gate.confidence_level == 'high'

    candidates.select do |incident|
      incident.scope_groups.any? do |group|
        group.criteria.any? { |criterion| semantic_gate.allowed_match_sources.include?(criterion.criterion_type) }
      end
    end
  end

  def semantic_scope(scope, classification)
    scope = scope.where('problem_types @> ARRAY[?]::text[]', classification['problem_type'])
    service_key = classification['service_key']
    return scope.where('cardinality(affected_services) = 0') unless TechnicalIncident::SERVICE_KEYS.include?(service_key)

    scope.where('cardinality(affected_services) = 0 OR affected_services @> ARRAY[?]::text[]', service_key)
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

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
  end
end
